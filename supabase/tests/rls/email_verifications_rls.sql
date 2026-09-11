-- Contact-email verification (#27): table access, the two RPCs, and the properties that
-- make verification mean anything.
--
-- The central one is "a requester cannot read their own verification token back". The
-- original implementation returned the raw token to the caller, so anyone could confirm an
-- address they did not control — the feature verified nothing. The token now stays inside
-- the database and the queued email row is attributed to nobody, so no SELECT policy
-- branch matches it. If a future change re-links that row to its requester, the readback
-- test here is what catches it — and pending_email_verification, added alongside the resend
-- affordance, gets the same treatment: its result is asserted to carry NO key beyond the
-- handful the interface needs, so "just add the email id, it's harmless" fails here first.
--
-- The row is now kept after BOTH endings (success and expiry) rather than deleted, because
-- deleting it destroyed the only record that a scholar had asked for anything — which is what
-- a Resend button hangs on. Several tests below exist purely to pin that down.

\ir ../_helpers/helpers.sql.inc

begin;

create extension if not exists pgtap
with
	schema extensions;

select
	plan (27);

-- queue_thanks_emails' AFTER trigger posts to the resend edge function via net.http_post
-- using vault secrets the RLS CI job does not set, so it raises. request_email_verification
-- inserts into public.emails too; disable the trigger for the duration of this file.
alter table public.emails
disable trigger send_on_email_insert;

-- request_email_verification builds its link from the `site_url` vault secret and refuses
-- to run without one. Seed a value if the environment has not, so these tests exercise
-- behavior rather than deployment configuration: supabase/config.toml seeds it locally from
-- LOCAL_SITE_URL, but the RLS job runs `supabase start` with no env file, so there is none.
-- Rolled back with the rest of the transaction.
select
	vault.create_secret ('http://localhost:5173', 'site_url')
where
	not exists (
		select
			1
		from
			vault.secrets
		where
			name = 'site_url'
	);

select
	tests.create_scholar ('verify_self@test.local') as self \gset

select
	tests.create_scholar ('verify_other@test.local') as other \gset

-- ---- Direct table access is denied outright -------------------------------------
-- RLS is enabled with NO policies, so the table is unreachable except through the
-- SECURITY DEFINER RPCs.
select
	is (
		(select count(*)::int from public.email_verifications where scholar = :'self'),
		0,
		'this scholar has no pending verification to begin with'
	);

select
	tests.authenticate_as (:'self');

select
	is_empty (
		$$ select * from public.email_verifications $$,
		'an authenticated scholar cannot read email_verifications'
	);

-- ---- request_email_verification -------------------------------------------------
select
	lives_ok (
		$$ select public.request_email_verification('Candidate@Uni.EDU') $$,
		'a scholar can request verification of a contact email'
	);

select
	tests.clear_authentication ();

select
	is (
		(select candidate_email from public.email_verifications where scholar = :'self'),
		'candidate@uni.edu',
		'the candidate address is stored lowercased'
	);

select
	isnt (
		(select token_hash from public.email_verifications where scholar = :'self'),
		null,
		'a token hash is recorded'
	);

-- scholars.email is untouched until the candidate is actually confirmed.
select
	is (
		(select email from public.scholars where id = :'self'),
		'verify_self@test.local',
		'the previously verified address is preserved while a request is pending'
	);

-- The queued email is attributed to nobody, so no branch of the emails SELECT policy
-- (recipient, sender, or venue admin) can match it. This is what keeps the token secret.
select
	is (
		(
			select count(*)::int
			from public.emails
			where event = 'VerifyEmail' and (scholar is not null or sender is not null)
		),
		0,
		'the verification email is attributed to no scholar and no sender'
	);

select
	tests.authenticate_as (:'self');

select
	is_empty (
		$$ select * from public.emails where event = 'VerifyEmail' $$,
		'the requester cannot read their own verification email, and so cannot read the token'
	);

-- Rate limiting: a second request inside the cooldown is refused.
select
	throws_ok (
		$$ select public.request_email_verification('again@uni.edu') $$,
		'P0001',
		null,
		'a rapid second request is refused by the cooldown'
	);

select
	tests.authenticate_as_anon ();

select
	throws_ok (
		$$ select public.request_email_verification('anon@uni.edu') $$,
		'42501',
		null,
		'an anonymous caller cannot request verification'
	);

-- ---- The request that was just made -------------------------------------------
-- Read as the table owner, not as a scholar: RLS on this table is deny-all, so every one of
-- these would silently come back NULL under an authenticated or anon session — and an
-- assertion that something IS null would then pass for entirely the wrong reason.
select
	tests.clear_authentication ();

-- The lifetime is stated twice in SQL: the expires_at column default and the explicit value
-- request_email_verification writes. Nothing can pin prose to a column default, but this
-- pins those two to each other and to the intended number.
select
	is (
		(select expires_at - created_at from public.email_verifications where scholar = :'self'),
		interval '24 hours',
		'the link is valid for 24 hours'
	);

select
	is (
		(select verified_at from public.email_verifications where scholar = :'self'),
		null,
		'a fresh request is not yet confirmed'
	);

-- The pointer to the message that carried the link, which is how a scholar can be told the
-- mail never left the building. It points verification -> email and never the other way.
select
	is (
		(
			select e.event
			from public.email_verifications v
			join public.emails e on e.id = v.email_id
			where v.scholar = :'self'
		),
		'VerifyEmail',
		'the request records which email carried its link'
	);

-- Captured here, while the table is readable, so the cooldown assertion below can compare
-- the RPC's answer against the row without needing to read it from inside a session that
-- cannot.
select created_at + interval '1 minute' as resend_after from public.email_verifications where scholar = :'self' \gset

-- ---- pending_email_verification -------------------------------------------------
select
	tests.authenticate_as (:'self');

select
	is (
		(select public.pending_email_verification() ->> 'email'),
		'candidate@uni.edu',
		'a scholar can see the address they are waiting to verify'
	);

select
	is (
		(select public.pending_email_verification() -> 'pending'),
		'true'::jsonb,
		'that request reads as pending'
	);

-- The cooldown is returned as an instant rather than a duration, so a countdown targets the
-- same moment the RPC starts accepting again instead of re-deriving "one minute" in the
-- browser and disagreeing with the database by a second.
select
	is (
		(select (public.pending_email_verification() ->> 'resend_after')::timestamptz),
		:'resend_after'::timestamptz,
		'the cooldown is reported as the instant it lifts'
	);

-- The direct descendant of the token-readback test above. The function must return the
-- caller's own row and NOTHING else: not the token hash, not the id of the email whose args
-- carry the raw link, not the edge function's delivery diagnostics. Asserting the whole key
-- set rather than three absences means a future addition has to be argued for here.
select
	is_empty (
		$$
		select key from jsonb_object_keys(public.pending_email_verification()) as key
		except
		select unnest(array['pending','email','created_at','expires_at','expired','resend_after','delivery'])
		$$,
		'the pending request exposes no key beyond the ones the interface needs'
	);

select
	tests.authenticate_as (:'other');

select
	is (
		(select public.pending_email_verification() -> 'pending'),
		'false'::jsonb,
		'a different scholar sees their own absent request, not this one'
	);

select
	tests.authenticate_as_anon ();

select
	throws_ok (
		$$ select public.pending_email_verification() $$,
		'42501',
		null,
		'an anonymous caller cannot ask what is pending'
	);

-- ---- verify_email ---------------------------------------------------------------
-- Callable by anon: the link is routinely followed in a browser with no session.
select
	tests.clear_authentication ();

select substring(args ->> 0 from '/verify/([a-f0-9]+)') as raw_token from public.emails where event = 'VerifyEmail' and email = 'candidate@uni.edu' limit 1 \gset

select
	is (
		(select public.verify_email(:'raw_token') ->> 'status'),
		'verified',
		'a valid token verifies'
	);

select
	is (
		(select email from public.scholars where id = :'self'),
		'candidate@uni.edu',
		'the candidate address is committed to scholars.email'
	);

-- Stamped rather than deleted, which is how "pending" stays answerable now that the row
-- survives success.
select
	isnt (
		(select verified_at from public.email_verifications where scholar = :'self'),
		null,
		'confirming stamps the request rather than removing it'
	);

select
	tests.authenticate_as (:'self');

select
	is (
		(select public.pending_email_verification() -> 'pending'),
		'false'::jsonb,
		'nothing is pending once the candidate is confirmed'
	);

select
	tests.clear_authentication ();

-- ---- Expiry keeps the row ---------------------------------------------------------
-- This is the assertion the whole resend affordance rests on. Expiry used to DELETE the
-- request, which threw away the only evidence the scholar had ever asked for anything and
-- left the interface with nothing to offer but a blank form.
--
-- Confirmed rows win over the clock, so clear the stamp before winding time back; otherwise
-- this would exercise the verified-first branch instead of the expiry branch.
update public.email_verifications
set
	verified_at = null,
	expires_at = now() - interval '1 minute'
where
	scholar = :'self';

select
	is (
		(select public.verify_email(:'raw_token') ->> 'status'),
		'expired',
		'a lapsed token reports itself expired'
	);

select
	is (
		(select count(*)::int from public.email_verifications where scholar = :'self'),
		1,
		'an expired request survives, so there is something left to send again'
	);

select
	tests.authenticate_as (:'self');

select
	is (
		(select public.pending_email_verification() -> 'expired'),
		'true'::jsonb,
		'the scholar is told their pending link has lapsed'
	);

select
	tests.clear_authentication ();

-- A confirmed request stays confirmed however long afterwards the same message is reopened.
-- Unreachable before this change (the row was deleted on expiry), and wrong if it regresses:
-- a scholar would be told a link expired for an address that is already theirs.
update public.email_verifications
set
	verified_at = now()
where
	scholar = :'self';

select
	is (
		(select public.verify_email(:'raw_token') ->> 'status'),
		'verified',
		'a long-since-confirmed link still reports verified, not expired'
	);

select
	*
from
	finish ();

rollback;
