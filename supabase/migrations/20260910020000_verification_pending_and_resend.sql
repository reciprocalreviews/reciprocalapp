--------------------------------------
-- Contact-email verification: 24-hour links, persistent pending state, and a resend (#27).
--
-- Three faults compounded here. The link lived 15 minutes, measured from the moment the row
-- was written rather than the moment the mail arrived — with a best-effort pg_net POST, an
-- edge function cold start, Resend's queue and the recipient's greylisting all in between.
-- There was no resend affordance anywhere: request_email_verification has always BEEN the
-- resend path (its upsert on the scholar primary key resets the token and clock), but the
-- only way to reach it was to retype the address. And verify_email DELETED the row on expiry,
-- which — with this table under deny-all RLS and no read RPC — left the application with no
-- memory that a verification had ever been requested. A scholar who missed the window came
-- back to an empty form and no sign of which address was waiting.
--
-- This migration: raises the lifetime to 24 hours; keeps the row after BOTH endings and adds
-- verified_at to tell them apart; links each request to the public.emails row its link went
-- out in so delivery failure can be surfaced; and adds public.pending_email_verification() so
-- the interface can show what is pending and offer to send it again.
--
-- Also closes an erasure gap this change makes findable — see forget_scholar below.
--
-- Paired with supabase/schemas/email_verifications.sql and supabase/schemas/erasures.sql.
-- Must run AFTER 20260910010000_email_delivery_status.sql: email_id has a foreign key to
-- public.emails(id), and pending_email_verification() reads public.emails.delivery.
--------------------------------------
-- 15 minutes -> 24 hours. Restated in the insert inside request_email_verification below;
-- a pgTAP assertion pins the two to each other.
alter table public.email_verifications
alter column expires_at
set default (now() + interval '24 hours');

-- Pending is now `verified_at is null`, not "a row exists": the row survives success (so a
-- mail scanner's prefetch cannot burn the link) and, as of this migration, survives expiry
-- too (so there is something for a Resend button to hang on).
alter table public.email_verifications
add column if not exists verified_at timestamp with time zone;

-- Which public.emails row carried this request's link, so its delivery status can be read
-- back. ON DELETE SET NULL rather than CASCADE: the mail log is evidence and the pending
-- request is state — losing the pointer should cost a delivery status, not the verification.
alter table public.email_verifications
add column if not exists email_id uuid;

alter table public.email_verifications
drop constraint if exists email_verifications_email_fkey;

alter table public.email_verifications
add constraint email_verifications_email_fkey foreign key (email_id) references public.emails (id) on delete set null;

-- Backfill, and NOT optional. The row has always been kept on success, so every project has
-- rows here whose candidate was confirmed under code that recorded nothing. Without this they
-- would read as pending forever, and every such scholar would open their profile to be told a
-- link is on its way for an address they verified weeks ago. A local `npm run reset` will not
-- reveal that; only a database with history will.
--
-- created_at rather than now(): we do not know when they confirmed, but we do know it was not
-- this moment, and the request time is the closest defensible answer.
update public.email_verifications v
set
	verified_at = v.created_at
from
	public.scholars s
where
	s.id = v.scholar
	and s.email is not null
	and lower(s.email) = lower(v.candidate_email)
	and v.verified_at is null;

--------------------------------------
-- request_email_verification: create (or replace) a pending verification for the
-- authenticated scholar and QUEUE the branded email. Returns nothing: the raw token never
-- leaves the database. An earlier version returned it to the browser, which let anyone
-- read it from the network tab and confirm an address they did not control — defeating the
-- entire purpose of verifying. For the same reason the caller supplies neither the message
-- body nor the link's origin: this email's recipient is whatever address the caller typed,
-- so letting them choose the content too would make the pipeline an open relay.
--
-- Does NOT touch scholars.email — the old verified value is kept until the new address is
-- confirmed. Doubles as the "resend" and "change email" entry point (upsert on the scholar
-- primary key resets the token and the 24-hour clock), which is what the Resend button on
-- the profile and on the expired-link page both call.
--
-- Records which public.emails row the link went out in, so public.pending_email_verification()
-- can tell the scholar when the message never left the building. That row stays attributed to
-- nobody; see the comment on the insert below.
--
-- Each failure carries a machine-readable `hint` so the interface can say which of the four
-- things went wrong. Without it every case collapsed into one generic "unable to send",
-- which told a rate-limited scholar nothing and made a missing vault secret look like a
-- transient delivery fault.
create or replace function public.request_email_verification (_email text) returns void language "plpgsql" security definer
set
	"search_path" to 'public',
	'pg_temp' as $$
declare
	_caller uuid := (select auth.uid());
	_token text;
	_origin text := private.get_secret('site_url');
	_previous timestamptz;
	-- Minted here rather than taken from the insert's RETURNING, because the foreign key
	-- runs the other way: email_verifications.email_id references public.emails(id), so the
	-- email row has to exist first. Generating the id up front lets both writes name it
	-- without a second statement to stitch them together.
	_email_id uuid := gen_random_uuid();
begin
	if _caller is null then
		raise exception 'Authentication required' using hint = 'auth_required';
	end if;
	if _email is null or _email !~ '^.+@.+\..+$' then
		raise exception 'A valid email address is required' using hint = 'invalid_email';
	end if;
	-- A deployment that has not had its `site_url` vault secret set cannot build a
	-- verification link. Say so, rather than letting it look like a delivery failure.
	if _origin is null or _origin = '' then
		raise exception 'The site_url vault secret is not configured' using hint = 'not_configured';
	end if;

	-- Rate limit. Each call emails an address the caller chose, so without a cooldown this
	-- RPC is a mail amplifier. One per minute is well below any legitimate resend cadence.
	select created_at into _previous from public.email_verifications where scholar = _caller;
	if _previous is not null and _previous > now() - interval '1 minute' then
		raise exception 'Please wait a moment before requesting another verification email' using hint = 'cooldown';
	end if;

	_token := encode(extensions.gen_random_bytes(32), 'hex');

	-- The email row goes FIRST, for the foreign key above. Both writes are in one
	-- transaction, so a failure on either leaves neither — no message goes out for a
	-- verification that does not exist, and no verification waits on a message that was
	-- never queued.
	--
	-- scholar AND sender are deliberately null: the emails SELECT policy grants reads to
	-- both the recipient and the sender, so attributing this row to the requester would let
	-- them read the token back out of the args — the very leak this design closes. With
	-- both null no policy branch matches and the row is unreadable by anyone. The id being
	-- recorded next door does not change that: email_verifications is itself unreadable
	-- (RLS enabled, no policies), and pending_email_verification() never returns the id.
	insert into public.emails (id, event, scholar, sender, venue, email, subject, message, args)
	values (
		_email_id,
		'VerifyEmail',
		null,
		null,
		null,
		lower(btrim(_email)),
		null,
		null,
		jsonb_build_array(rtrim(_origin, '/') || '/verify/' || _token)
	);

	insert into public.email_verifications (scholar, token_hash, candidate_email, created_at, expires_at, verified_at, email_id)
	values (
		_caller,
		encode(extensions.digest(_token, 'sha256'), 'hex'),
		lower(btrim(_email)),
		now(),
		-- Pinned to the column default by a pgTAP assertion; see the note on expires_at.
		now() + interval '24 hours',
		null,
		_email_id
	)
	on conflict (scholar) do update
		set token_hash = excluded.token_hash,
			candidate_email = excluded.candidate_email,
			created_at = excluded.created_at,
			expires_at = excluded.expires_at,
			-- Reset on every request, including a resend of the SAME address. Without this
			-- a scholar who verified, then asked to change to a new address, would have the
			-- new request inherit the old confirmation and read as already done.
			verified_at = excluded.verified_at,
			email_id = excluded.email_id;
end;
$$;

alter function public.request_email_verification (text) OWNER to "postgres";

revoke
execute on function public.request_email_verification (text)
from
	public,
	anon;

grant
execute on function public.request_email_verification (text) to authenticated;

--------------------------------------
-- verify_email: consume a token. Callable by anon because the link may be clicked while
-- logged out. Validates the token and its expiry; on success copies the candidate into
-- scholars.email. Returns a discriminated status so the verify page can render distinct UI.
-- The 256-bit token makes enumeration infeasible.
--
-- It no longer DELETES anything. Both endings leave the row in place, which is what lets the
-- interface offer "send it again" instead of an empty form — see verified_at on the table.
create or replace function public.verify_email (_token text) RETURNS jsonb LANGUAGE "plpgsql" SECURITY DEFINER
set
	"search_path" to 'public',
	'pg_temp' as $$
declare
	_row public.email_verifications%rowtype;
begin
	select * into _row from public.email_verifications
	where token_hash = encode(extensions.digest(_token, 'sha256'), 'hex');

	if not found then
		return jsonb_build_object('status', 'invalid');
	end if;

	-- Already confirmed: say so, whatever the clock says. This branch comes FIRST
	-- deliberately, and it is new. Verification has always been idempotent so that an email
	-- scanner's prefetch cannot burn the link, but the row used to be deleted on expiry, so
	-- "verified, then expired" was unreachable. Now that the row survives, a scholar who
	-- verified an hour after the link was sent and reopened the same message two days later
	-- would be told it had expired — which is false, and which would send them to a resend
	-- button for an address that is already theirs.
	if _row.verified_at is not null then
		return jsonb_build_object(
			'status', 'verified',
			'scholar', _row.scholar,
			'email', _row.candidate_email
		);
	end if;

	-- Expired, and the row is KEPT where it used to be deleted. Deleting it threw away the
	-- only evidence the scholar had asked for anything, so the only thing the interface
	-- could offer was a blank form. Keeping it costs one row per scholar — `scholar` is the
	-- primary key, so a later request replaces this one rather than adding to it, and the
	-- table cannot grow past the number of scholars — and it leaks nothing: the candidate is
	-- an address the scholar typed into their own profile, the token is stored as a hash,
	-- and that hash is now useless. Erasure still removes the row (erasures.sql).
	if _row.expires_at < now() then
		return jsonb_build_object('status', 'expired');
	end if;

	-- Idempotent commit: still no delete, so a repeat fetch within the validity window
	-- (email link scanner prefetch, or SvelteKit hover-preload) returns 'verified' rather
	-- than a misleading 'invalid'. A later request replaces this row (upsert on the
	-- scholar PK).
	update public.scholars set email = _row.candidate_email where id = _row.scholar;

	-- Stamped rather than deleted, so pending_email_verification() can tell a confirmed row
	-- from one still waiting. coalesce keeps the FIRST confirmation time under a re-fetch.
	update public.email_verifications
	set verified_at = coalesce(verified_at, now())
	where scholar = _row.scholar;

	return jsonb_build_object(
		'status', 'verified',
		'scholar', _row.scholar,
		'email', _row.candidate_email
	);
end;
$$;

alter function public.verify_email (text) OWNER to "postgres";

revoke
execute on function public.verify_email (text)
from
	public;

grant
execute on function public.verify_email (text) to anon,
authenticated;

--------------------------------------
-- pending_email_verification: what, if anything, the CALLER is waiting to verify.
--
-- The counterpart to request_email_verification, and the reason the request row now outlives
-- both of its endings. Before this the client could see NOTHING: email_verifications has RLS
-- enabled with no policies, request_email_verification returns void, and "sent" was a boolean
-- in component memory. So a reload — or opening the profile on a phone after reading the
-- email on a laptop — showed a scholar the same empty form they had already filled in, with
-- no sign that a link was on its way, no way to ask for another, and no way to find out which
-- address they had typed.
--
-- Returns the caller's own row and NOTHING ELSE. Three omissions are deliberate:
--
--   * token_hash, and anything derived from it. It is the secret this whole design exists to
--     keep inside the database; an earlier version of this feature returned the raw token to
--     the browser, which let anyone read it out of the network tab and confirm an address
--     they did not control.
--   * email_id. It names a row in public.emails whose `args` carry the raw link. The scholar
--     cannot read that row — it is attributed to nobody precisely so no policy branch matches
--     — and handing them its primary key is an invitation to a future change that joins it.
--   * delivery_detail. That is the edge function's own diagnostics and can quote a response
--     body. `delivery`, one of four words, is everything the interface needs to say "this
--     never left the building".
--
-- SECURITY DEFINER because neither table is readable by the caller. Keyed on auth.uid() and
-- takes no argument, so there is no other scholar's row that could be asked for.
create or replace function public.pending_email_verification () returns jsonb language plpgsql security definer stable
set
	"search_path" to '' as $$
declare
	_caller uuid := (select auth.uid());
	_row public.email_verifications%rowtype;
	_delivery text;
begin
	if _caller is null then
		raise exception 'Authentication required' using hint = 'auth_required';
	end if;

	select * into _row from public.email_verifications where scholar = _caller;

	-- Nothing pending: no row, or one whose candidate has already been confirmed. The row is
	-- kept after success so a re-fetched link still verifies, so its existence is not the
	-- question — verified_at is.
	if not found or _row.verified_at is not null then
		return jsonb_build_object('pending', false);
	end if;

	-- The coarse status of this request's own message, and only that. Reading public.emails
	-- here is safe for the same reason the rest of this function is: the column list is
	-- explicit and `args` is not in it.
	if _row.email_id is not null then
		select e.delivery into _delivery from public.emails e where e.id = _row.email_id;
	end if;

	return jsonb_build_object(
		'pending', true,
		'email', _row.candidate_email,
		'created_at', _row.created_at,
		'expires_at', _row.expires_at,
		-- Computed here rather than by comparing clocks in the browser. A device with a
		-- skewed clock would otherwise show a live link as expired, or worse.
		'expired', _row.expires_at < now(),
		-- The cooldown as an INSTANT, not a duration. request_email_verification refuses a
		-- second request within one minute of created_at; returning the moment it stops
		-- refusing lets the interface count down to exactly that, instead of re-deriving
		-- "one minute" somewhere else and disagreeing with the database by a second — which
		-- is the difference between a button that works when it lights up and one that
		-- answers with an error.
		'resend_after', _row.created_at + interval '1 minute',
		'delivery', _delivery
	);
end;
$$;

alter function public.pending_email_verification () OWNER to "postgres";

-- Revoked from authenticated too, then granted back, so the grant below is the whole truth
-- about who may call this. Supabase's default privileges grant anon and authenticated
-- EXECUTE at creation time and `revoke ... from public` does not take those back — see
-- 20260831000000, and supabase/tests/rls/definer_grants.sql, whose first check is what fails
-- if this line is ever dropped.
revoke
execute on function public.pending_email_verification ()
from
	public,
	anon,
	authenticated;

grant
execute on function public.pending_email_verification () to authenticated;

--------------------------------------
-- forget_scholar: redact the verification email too.
--
-- The VerifyEmail row is attributed to NOBODY — null scholar, null sender, so that no branch
-- of the emails SELECT policy matches it and the requester cannot read the token back out of
-- `args`. That is a deliberate security property, and it meant the existing redaction pass,
-- keyed on exactly those two columns, never touched it: an erased scholar's unverified
-- candidate address survived in `email` and the raw verification URL in `args`, indefinitely.
-- email_verifications.email_id, added above, is what makes it findable.
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

	-- The verification email itself. It is attributed to NOBODY — null scholar, null sender,
	-- so that no branch of the emails SELECT policy matches it and the requester cannot read
	-- the token back out of `args` — which means the redaction pass below, keyed on exactly
	-- those two columns, has never touched it. An erased scholar's unverified candidate
	-- address therefore survived in `email`, and the raw verification URL in `args`,
	-- indefinitely. email_verifications.email_id is what makes it findable (#27).
	--
	-- Runs BEFORE the delete below, because it reads the row being deleted.
	update public.emails
	set
		email = _placeholder,
		args = '[]'::jsonb
	where
		id in (
			select email_id from public.email_verifications
			where scholar = _scholar and email_id is not null
		);

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
