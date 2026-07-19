-- Contact-email verification (#27): table access, the two RPCs, and the properties that
-- make verification mean anything.
--
-- The central one is "a requester cannot read their own verification token back". The
-- original implementation returned the raw token to the caller, so anyone could confirm an
-- address they did not control — the feature verified nothing. The token now stays inside
-- the database and the queued email row is attributed to nobody, so no SELECT policy
-- branch matches it. If a future change re-links that row to its requester, the readback
-- test here is what catches it.

\ir ../_helpers/helpers.sql.inc

begin;

create extension if not exists pgtap
with
	schema extensions;

select
	plan (12);

-- queue_thanks_emails' AFTER trigger posts to the resend edge function via net.http_post
-- using vault secrets the RLS CI job does not set, so it raises. request_email_verification
-- inserts into public.emails too; disable the trigger for the duration of this file.
alter table public.emails
disable trigger send_on_email_insert;

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

select
	*
from
	finish ();

rollback;
