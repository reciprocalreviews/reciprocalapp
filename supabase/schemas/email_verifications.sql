--------------------------------------
-- TABLE
-- App-level contact-email verification (#27). This is deliberately independent of
-- Supabase auth: scholars authenticate with ORCID (which does not release an email),
-- so we collect a contact email separately and verify ownership ourselves. The
-- invariant that makes the rest of the app simple: public.scholars.email holds only a
-- VERIFIED address (or null) — this table holds the pending, not-yet-verified candidate
-- and a hash of the emailed token. On successful verification the candidate is copied
-- into scholars.email; until then the previously verified email (if any) is preserved.
--
-- The raw token lives only in the emailed URL; we store just its sha256 hash. There is
-- at most one active request per scholar (primary key on scholar), so re-requesting
-- (resend, or changing to a different address) simply replaces it and resets the clock.
create extension if not exists pgcrypto
with
	schema extensions;

create table if not exists public.email_verifications (
	-- The scholar requesting verification; one active request each.
	scholar uuid not null,
	-- sha256 hex hash of the raw token that was emailed.
	token_hash text not null,
	-- The unverified address awaiting confirmation.
	candidate_email text not null,
	-- When the request was made. Also the cooldown clock and, for the interface, the
	-- "we sent this N minutes ago" the scholar sees.
	created_at timestamp with time zone default now() not null,
	-- When the link expires: 24 hours, raised from 15 minutes (#27). Fifteen minutes was
	-- shorter than the gap between reading a notification on a phone and getting back to a
	-- computer, and it was measured from the moment the row was written rather than from
	-- the moment the mail arrived -- with a best-effort pg_net POST, an edge function cold
	-- start, Resend's queue and the recipient's greylisting all in between. And because the
	-- request row was DELETED on expiry, the scholar who missed the window arrived at a dead
	-- end: an empty form with no memory that they had already asked. Both halves of that are
	-- fixed here; this is the first half.
	--
	-- Restated in two places that cannot read a column default: the email body
	-- (supabase/functions/_shared/templates.ts, VerifyEmail) and the help article
	-- (src/routes/[[lang]]/help/articles/your-contact-email.md). The value written in
	-- request_email_verification below is pinned to this one by a pgTAP assertion in
	-- supabase/tests/rls/email_verifications_rls.sql; the prose is pinned by
	-- src/email/templates.unit.ts. Nothing can pin prose to a column default, so the number
	-- is stated four times on purpose and checked three.
	expires_at timestamp with time zone default (now()+interval '24 hours') not null,
	-- When this candidate was confirmed, or null while it is still pending.
	--
	-- Needed because the row now outlives BOTH of its endings. It is kept after success
	-- (verification has always been idempotent, so a mail scanner's prefetch cannot burn the
	-- link) and, as of this change, kept after expiry too -- because deleting it destroyed
	-- the only record that this scholar had ever asked for anything, which is exactly the
	-- state a "send it again" button hangs on. With the row surviving both, its mere
	-- existence no longer answers "is something pending?". This column does.
	verified_at timestamp with time zone,
	-- The public.emails row this request's link went out in, so a scholar can be told when
	-- the message never left the building (public.emails.delivery).
	--
	-- The pointer goes THIS way on purpose. That email row is deliberately attributed to
	-- nobody -- null scholar, null sender -- so that no branch of the emails SELECT policy
	-- matches it and the requester cannot read the token back out of `args`. Pointing from
	-- here to there adds no policy branch and changes nothing about that; and
	-- public.pending_email_verification() returns only the coarse delivery status, never
	-- this id, precisely so a later change cannot be tempted to "helpfully" join on it.
	email_id uuid
);

alter table public.email_verifications OWNER to "postgres";

alter table only public.email_verifications
add constraint "email_verifications_pkey" primary key ("scholar");

alter table only public.email_verifications
add constraint "email_verifications_scholar_fkey" foreign KEY ("scholar") references public.scholars ("id") on delete cascade;

-- ON DELETE SET NULL rather than CASCADE: the mail log is evidence and the pending request
-- is state. Losing the pointer should cost the scholar a delivery status, not their pending
-- verification.
alter table only public.email_verifications
add constraint "email_verifications_email_fkey" foreign KEY ("email_id") references public.emails ("id") on delete set null;

create index email_verifications_token_hash_index on public.email_verifications using btree (token_hash);

grant all on table public.email_verifications to "anon";

grant all on table public.email_verifications to "authenticated";

grant all on table public.email_verifications to "service_role";

--------------------------------------
-- SECURITY
-- Enable RLS with NO policies for anon/authenticated: all direct access is denied.
-- The table holds a secret token hash and an unverified address, so it is reachable
-- only through the SECURITY DEFINER RPCs below (owner postgres).
alter table public.email_verifications ENABLE row LEVEL SECURITY;

--------------------------------------
-- FUNCTIONS
--
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
	_previous text;
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
	select email into _previous from public.scholars where id = _row.scholar;

	update public.scholars set email = _row.candidate_email where id = _row.scholar;

	-- Tell the address that just stopped receiving this scholar's mail.
	--
	-- It is the only party with no other way to find out: the new address gets everything from
	-- here on, the scholar sees their profile, and the old address simply goes quiet -- which
	-- is indistinguishable from a takeover. Consequential, so no preference is consulted.
	--
	-- Safe to put after the early return above: a repeat fetch inside the validity window
	-- exits at `verified_at is not null` and never reaches here, so the notice is sent once.
	-- Nothing is sent on a first-ever verification (_previous is null) or a re-verification of
	-- the same address.
	if _previous is not null and _previous <> _row.candidate_email then
		insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
		values (
			'EmailChanged', _row.scholar, null, null, _previous, null, null,
			to_jsonb(array[_row.candidate_email])
		);
	end if;

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
