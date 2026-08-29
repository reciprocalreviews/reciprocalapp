-- Data portability and the right to be forgotten.
--
-- The terms page has promised both since it was written (static/locales/en.json,
-- page.terms.paragraph.retention and .rights) and neither existed. This is the
-- machinery; the scholar-facing flows call into it.
--
-- ERASURE IS ANONYMISATION IN PLACE, NOT DELETION, and that is forced by the data
-- rather than chosen for convenience. Fourteen tables reference scholars(id) —
-- among them transactions.creator, which is NOT NULL, and assignments, conflicts,
-- supporters, thanks and volunteers. A scholar's participation is woven into other
-- people's records: the transaction that paid a reviewer, the submission with
-- co-authors, the thank-you note someone else received. Deleting the row would
-- either fail on those constraints or destroy records belonging to other people.
--
-- So the row survives as an anonymous tombstone: the identifiers that make it a
-- person (name, email, ORCID, free-text status, and the auth identity behind it)
-- are destroyed, and what remains is a uuid that no longer refers to anyone. That
-- is what the terms already describe as transaction records being "de-linked".
--
-- THE LEDGER IS DELIBERATELY LEFT ALONE, apart from `actor`. An earlier sketch of
-- this work proposed nulling token_events.scholar and prev_scholar; doing so would
-- corrupt the ledger outright. tokens_as_of() reconstructs ownership from exactly
-- those columns, so nulling them would make the most recent event for every one of
-- the scholar's tokens claim no owner — reconcile_ledger()'s replay check would
-- fail, and the tokens would become unexplainable. The columns hold uuids, which
-- refer to nobody once the tombstone is scrubbed, so there is nothing to erase.
--
-- Tokens stay with the tombstone for the same reason: they are currency rather
-- than personal data, and moving them would silently change a venue's reserve.
--------------------------------------
-- A record of every erasure, kept so it can be RE-APPLIED after a restore.
--
-- This is the part that is easy to miss: a backup taken before an erasure still
-- contains the person. Restoring it brings them back, and the platform would then
-- be holding data it told someone it had destroyed. Re-applying this list is a
-- mandatory step of every restore (RECOVERY.md § Restoring).
--
-- No foreign key to scholars, on purpose — the same reasoning as the logs. This
-- has to outlive the row it refers to, and survive a restore that does not yet
-- contain it.
create table if not exists public.erasures (
	id uuid primary key default gen_random_uuid(),
	subject uuid not null,
	requested_at timestamptz not null default now(),
	completed_at timestamptz,
	-- Free text for a steward-initiated erasure: who asked, and how.
	note text
);

alter table public.erasures OWNER to "postgres";

create unique index erasures_subject_unique on public.erasures using btree (subject);

alter table public.erasures ENABLE row LEVEL SECURITY;

-- Nobody reads this through the API: it is a list of people who asked to be
-- forgotten, which would be a poor thing to publish.
revoke all on table public.erasures
from
	anon,
	authenticated;

-- Explicitly revoked, not merely un-granted: Supabase's default privileges give
-- service_role ALL on every new table in `public` before this grant runs. Same
-- correction as 20260808020000 made for the append-only logs.
revoke insert,
update,
delete on table public.erasures
from
	service_role;

grant
select
	on table public.erasures to service_role;

--------------------------------------
-- The worker. Owner-only: called by the RPC below, and by hand when re-applying
-- erasures after a restore.
create or replace function public.forget_scholar (_scholar uuid) returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_placeholder text := 'erased-' || _scholar || '@invalid';
	_emails int;
	_copied int;
	_audit int;
	_old_email text;
begin
	if _scholar is null then
		raise exception 'forget_scholar requires a scholar id';
	end if;

	-- Captured BEFORE the scholars row below is scrubbed. Mail where this scholar was
	-- merely copied, or was the person replies went to, is reachable only by address:
	-- emails.cc and emails.reply_to hold addresses, and neither is matched by the
	-- scholar/sender scrub further down.
	select email into _old_email from public.scholars where id = _scholar;

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
		args = '[]'::jsonb,
		-- Mail addressed TO this scholar may also have copied others and named a third
		-- party as its reply address. Neither belongs to the erased scholar, but both are
		-- contents of a message whose contents are being destroyed.
		cc = null,
		reply_to = null
	where scholar = _scholar or sender = _scholar;
	get diagnostics _emails = row_count;

	-- Mail about SOMEBODY ELSE that merely copied this scholar, or that replied to them.
	-- The rest of the row belongs to other people and stays; only this scholar's address
	-- leaves it. Without this pass an erased address survived indefinitely in notices about
	-- other scholars — the exact thing erasure exists to prevent.
	if _old_email is not null then
		update public.emails
		set
			cc = nullif(array_remove(cc, _old_email), '{}'::text[]),
			reply_to = case when reply_to = _old_email then null else reply_to end
		where (cc is not null and _old_email = any (cc))
			or reply_to = _old_email;
		get diagnostics _copied = row_count;
	else
		_copied := 0;
	end if;

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
		-- Reported separately from emails_scrubbed: these rows were not scrubbed, only
		-- de-addressed, and the receipt should not imply that mail about other people was
		-- emptied out.
		'emails_uncopied', _copied,
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

--------------------------------------
-- The scholar-facing entry point. A scholar may erase themselves; a steward may
-- erase anyone, for a request that arrives by post or by email.
create or replace function public.erase_scholar (
	_scholar uuid default null,
	_note text default null
) returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_caller uuid := (select auth.uid());
	_target uuid := coalesce(_scholar, _caller);
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	if _target <> _caller and not public.isSteward() then
		raise exception 'You can only erase your own account' using errcode = 'RR006';
	end if;

	insert into public.erasures (subject, note)
	values (_target, _note)
	on conflict (subject) do nothing;

	return public.forget_scholar(_target);
end;
$$;

alter function public.erase_scholar (uuid, text) OWNER to "postgres";

revoke
execute on function public.erase_scholar (uuid, text)
from
	public,
	anon;

grant
execute on function public.erase_scholar (uuid, text) to authenticated;

--------------------------------------
-- Portability: everything the platform holds about one scholar, in one document.
--
-- SECURITY DEFINER so it can read across tables whose policies would otherwise
-- hide a scholar's own assignments from them (venue anonymity rules are about
-- other people seeing them, not about them seeing themselves), with the same
-- self-or-steward check as erasure.
create or replace function public.export_scholar_data (_scholar uuid default null) returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_caller uuid := (select auth.uid());
	_target uuid := coalesce(_scholar, _caller);
	_target_email text;
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	if _target <> _caller and not public.isSteward() then
		raise exception 'You can only export your own data' using errcode = 'RR006';
	end if;

	-- Resolved once rather than per row: emails.cc holds addresses, not ids.
	select email into _target_email from public.scholars s where s.id = _target;

	return jsonb_build_object(
		'exported_at', now(),
		'scholar', (select to_jsonb(s) from public.scholars s where s.id = _target),
		'volunteering', (select coalesce(jsonb_agg(to_jsonb(v)), '[]'::jsonb) from public.volunteers v where v.scholarid = _target),
		'submissions', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.submissions x where _target = any (x.authors)),
		'assignments', (select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) from public.assignments a where a.scholar = _target),
		'conflicts', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from public.conflicts c where c.scholarid = _target),
		'supported_proposals', (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from public.supporters p where p.scholarid = _target),
		'thanks_written', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.thanks t where t.author = _target),
		'transactions', (select coalesce(jsonb_agg(to_jsonb(t) order by t.seq), '[]'::jsonb) from public.transactions t
			where t.creator = _target or t.from_scholar = _target or t.to_scholar = _target),
		'tokens_held', (select coalesce(jsonb_object_agg(currency, n), '{}'::jsonb)
			from (select currency, count(*) as n from public.tokens where scholar = _target group by currency) c),
		-- The ledger makes this possible for the first time: before token_events
		-- there was no record of where a scholar's tokens had been.
		'token_history', (select coalesce(jsonb_agg(to_jsonb(e) order by e.seq), '[]'::jsonb)
			from public.token_events e where e.scholar = _target or e.prev_scholar = _target),
		-- Addressed to them, or copied on it. `m.scholar` names only the To recipient, so
		-- before the cc branch a scholar's own export said nothing about notices they
		-- actually received. SECURITY DEFINER, so this scan is not limited by the emails
		-- SELECT policy — which is what lets it report mail the scholar received but cannot
		-- read the row for. Still only the event and the time: the export says what
		-- arrived, not what it said.
		'emails_received', (select coalesce(jsonb_agg(jsonb_build_object('event', m.event, 'time_sent', m.time_sent)), '[]'::jsonb)
			from public.emails m
			where m.scholar = _target
				or (_target_email is not null and m.cc is not null and _target_email = any (m.cc))),
		-- Which notices they have silenced. Small, but it is a preference they set, and so
		-- part of what the platform holds about them.
		'notification_settings', (select coalesce(jsonb_agg(to_jsonb(n)), '[]'::jsonb)
			from public.notification_settings n where n.scholar = _target)
	);
end;
$$;

alter function public.export_scholar_data (uuid) OWNER to "postgres";

revoke
execute on function public.export_scholar_data (uuid)
from
	public,
	anon;

grant
execute on function public.export_scholar_data (uuid) to authenticated;
