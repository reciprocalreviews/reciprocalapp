-- Stewards can appoint and remove stewards.
--
-- WHY
--
-- `scholars.steward` gates approving venue proposals, creating venues and
-- currencies, and erasing or exporting another scholar's data — and until now
-- nothing in the application could write it. 20260719010000 revoked the
-- table-wide UPDATE that let a scholar promote themselves and re-granted only
-- (name, available, status, status_time), which closed the hole and left no door:
-- stewardship could be conferred only by hand at a psql prompt or by seed data.
-- That migration named the fix it was deferring —
--
--   "a future steward tool for that belongs behind a SECURITY DEFINER RPC gated
--    on isSteward(), not a blanket table privilege"
--
-- — and this is that RPC. The column privileges are deliberately untouched: they
-- are what makes set_steward the only path, which is the whole point.
--
-- WHY ONE FUNCTION
--
-- The caller check, the existence check, the lock, and the audit story are
-- identical for promotion and demotion; the asymmetries are two branches. A
-- promote/demote pair would mean two owner/revoke/grant trios, two entries in the
-- generated types, and two copies of the same authorization test.
--
-- THE TWO DEMOTION GUARDS
--
-- Nobody may demote themselves: stepping down is an act another steward performs,
-- so it cannot happen by accident and a lone steward cannot strand the platform.
-- And the last steward may not be demoted at all, because with this function as
-- the only path, a database with zero stewards can never gain one back through
-- the API — recovery would mean a psql prompt.
--
-- The last-steward guard looks unreachable, and is not. Serially it is: demoting
-- X requires a steward caller other than X, so at least two exist and one always
-- survives. It earns its place in the concurrent case, and only alongside the
-- lock — see the comment on the `for update` below.
--
-- ERASURE MUST REVOKE STEWARDSHIP TOO
--
-- forget_scholar nulled name, email and orcid but never touched `steward`, so an
-- erased steward kept the privilege: the tombstone still satisfied isSteward()
-- and still rendered on the public /about list as "anonymous". Harmless-looking
-- until now — but a uuid nobody can sign into would satisfy the last-steward
-- guard, letting the last real steward be demoted while nobody is left to act.
-- Fixed here rather than inside set_steward because config.toml declares
-- schemas/scholars.sql first and schemas/erasures.sql last, and a schema file may
-- only reference tables declared above it.
--
-- Note this makes self-erasure by the last steward a lockout path, since
-- erase_scholar has no last-steward guard and deliberately keeps none: the right
-- to erasure is unconditional and should not be blocked by an operational
-- concern. service_role retains table-level UPDATE on scholars, so recovery is a
-- psql prompt away.
--------------------------------------
create or replace function public.set_steward (_scholar uuid, _steward boolean) returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_caller uuid := (select auth.uid());
	_current boolean;
	_remaining integer;
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- Lock every steward row, and the target, BEFORE deciding anything. Under READ
	-- COMMITTED each statement takes its own snapshot, so two stewards demoting each
	-- other concurrently would each see the other still standing, and both would
	-- succeed — leaving nobody, in a system where this function is the only way back
	-- to the column. Locking first serializes the function against itself: the second
	-- caller waits, then re-reads committed truth instead of its own stale snapshot.
	-- The lock set is tiny and these calls are rare, so the cost is a brief wait for
	-- a steward editing their own name at the same moment.
	perform 1 from public.scholars where steward or id = _scholar for update;

	-- After the lock, not before, so a caller demoted while it waited is refused.
	if not public.isSteward() then
		raise exception 'Only stewards can change who is a steward' using errcode = 'RR010';
	end if;

	select steward into _current from public.scholars where id = _scholar;
	if not found then
		raise exception 'No such scholar' using errcode = 'RR011';
	end if;

	-- Already so, and saying so is not a failure: the caller may simply be looking at
	-- a list that has moved on. `changed` lets the client tell a no-op from a write
	-- without a check-then-write race against a client-side "are they already?" test.
	if _current = _steward then
		return jsonb_build_object('scholar', _scholar, 'steward', _current, 'changed', false);
	end if;

	if not _steward then
		-- Stepping down is something another steward does for you, so nobody resigns
		-- by accident and a lone steward cannot strand the platform. Checked before
		-- the count, so a sole steward gets this message rather than the confusing
		-- "last steward" one.
		if _scholar = _caller then
			raise exception 'You cannot remove yourself as a steward' using errcode = 'RR013';
		end if;

		-- Unreachable serially — demoting X requires a steward caller other than X, so
		-- one always survives — and not dead code: it fires in the concurrent case the
		-- lock above serializes, where the caller's own stewardship was revoked while
		-- it waited. The guard and the lock only work together.
		select count(*) into _remaining
		from public.scholars
		where steward and id <> _scholar;
		if _remaining = 0 then
			raise exception 'The last steward cannot be demoted' using errcode = 'RR012';
		end if;
	end if;

	update public.scholars set steward = _steward where id = _scholar;

	-- Who did this, and when, is recorded for free: public.scholars is in the
	-- audit_log trigger's table list, and log_audit_event stores auth.uid(), which is
	-- the CALLER — security definer changes the current user, not the JWT claim.
	return jsonb_build_object('scholar', _scholar, 'steward', _steward, 'changed', true);
end;
$$;

alter function public.set_steward (uuid, boolean) OWNER to "postgres";

-- Revoking from `public` also drops service_role's implicit execute, which is
-- correct: service_role keeps table-level UPDATE on scholars from `grant all`
-- above, so the psql recovery path never needs this function.
revoke
execute on function public.set_steward (uuid, boolean)
from
	public,
	anon;

grant
execute on function public.set_steward (uuid, boolean) to authenticated;

--------------------------------------
-- Restated in full for the one added line — a function body cannot be ALTERed.
-- `create or replace` preserves the ACL, but the owner and revoke are repeated to
-- match the declaration in schemas/erasures.sql.
create or replace function public.forget_scholar (_scholar uuid) returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_placeholder text := 'erased-' || _scholar || '@invalid';
	_emails int;
	_audit int;
begin
	if _scholar is null then
		raise exception 'forget_scholar requires a scholar id';
	end if;

	-- The identity behind the account. The row stays so the foreign keys hold, but
	-- nothing in it points at a person any more, and the credentials are destroyed
	-- so the account cannot be used again.
	update auth.users
	set
		email = _placeholder,
		phone = null,
		encrypted_password = null,
		raw_user_meta_data = '{}'::jsonb,
		raw_app_meta_data = '{}'::jsonb,
		confirmation_token = '',
		recovery_token = '',
		email_change = ''
	where id = _scholar;

	-- ORCID is the login identity; `status` is free text the scholar wrote about
	-- themselves and can name anyone.
	update public.scholars
	set
		name = null,
		email = null,
		orcid = null,
		-- Erasure destroys the identity, so it must destroy the privilege with it. A
		-- tombstone that is still a steward appears on the public /about list as
		-- "anonymous", still satisfies isSteward(), and would satisfy set_steward's
		-- last-steward guard on behalf of a uuid nobody can sign into — letting the
		-- last real steward be demoted while nobody is left who can act.
		steward = false,
		-- Emptied rather than nulled: `status` is NOT NULL. It is free text the
		-- scholar wrote about themselves and can name anyone, so it has to go.
		status = '',
		available = false
	where id = _scholar;

	-- A pending verification holds an address that was never even confirmed.
	delete from public.email_verifications where scholar = _scholar;

	-- Queued and sent mail carries the address and, in `args`, rendered values that
	-- can include their name. The row stays as evidence that a message was sent;
	-- its contents do not.
	update public.emails
	set
		email = _placeholder,
		subject = null,
		message = null,
		args = '[]'::jsonb
	where scholar = _scholar or sender = _scholar;
	get diagnostics _emails = row_count;

	-- audit_log keeps WHOLE rows, so every edit this scholar's profile ever
	-- received contains their name and address. Scrub the payloads and the actor,
	-- leaving which table changed and when — the append-only guard permits exactly
	-- this much and nothing more.
	perform set_config('app.erasure', 'on', true);

	update public.audit_log
	set
		before = case when before is not null then '{}'::jsonb end,
		after = case when after is not null then '{}'::jsonb end
	where tbl = 'scholars' and row_id = _scholar;
	get diagnostics _audit = row_count;

	update public.audit_log set actor = null where actor = _scholar;

	-- token_events.actor is the only field here that names a person; the ownership
	-- columns are left untouched, because the ledger is reconstructed from them.
	update public.token_events set actor = null where actor = _scholar;

	perform set_config('app.erasure', '', true);

	insert into public.erasures (subject, completed_at)
	values (_scholar, now())
	on conflict (subject) do update set completed_at = now();

	return jsonb_build_object(
		'scholar', _scholar,
		'emails_scrubbed', _emails,
		'audit_payloads_scrubbed', _audit
	);
end;
$$;

alter function public.forget_scholar (uuid) OWNER to "postgres";

revoke
execute on function public.forget_scholar (uuid)
from
	public,
	anon,
	authenticated,
	service_role;
