-- Tests for the notification correctness fixes: public.decline_venue_proposal and the
-- EmailChanged notice public.verify_email now writes to the address it replaces.
--
-- What is under test:
--   DECLINE    a proposal's supporters AND its listed editor addresses are told, the
--              proposal is gone afterwards, a supporter who silenced the preference is
--              skipped, and somebody who is both a supporter and a listed editor gets one
--              message rather than two. Stewards only.
--   REPLACED   verifying a NEW contact address writes to the OLD one, names the new address
--              so the reader can report it, sends nothing on a first-ever verification, and
--              does not send again when the same link is fetched twice.
--
-- Inserting an email fires the send_on_email_insert AFTER trigger (net.http_post via the
-- `supabase_url` vault secret). The RLS CI job doesn't set that env, so the URL is null and
-- the post raises. Nothing here depends on mail being dispatched, so the trigger is disabled
-- for this rolled-back test, exactly as emails_rls.sql and new_volunteer_notice.sql do.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan (16);

alter table public.emails disable trigger send_on_email_insert;

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('nc_steward@test.local', true) as steward \gset
select tests.create_scholar('nc_support@test.local')       as supporter \gset
select tests.create_scholar('nc_muted@test.local')         as muted \gset
select tests.create_scholar('nc_both@test.local')          as both \gset
select tests.create_scholar('nc_other@test.local')         as other \gset

-- 'nc_both@test.local' is listed as an editor AND supports the proposal, which is the case
-- that would otherwise produce two copies of the same message.
insert into public.proposals (id, title, census, editors)
values (
	'00000000-0000-4000-8000-0000000000c1', 'Journal of Declines', 100,
	array['nc_editor@test.local', 'nc_both@test.local']
);

insert into public.supporters (scholarid, proposalid) values
	(:'supporter', '00000000-0000-4000-8000-0000000000c1'),
	(:'muted',     '00000000-0000-4000-8000-0000000000c1'),
	(:'both',      '00000000-0000-4000-8000-0000000000c1');

-- ProposalDeclined defers to VenueApproved via `silencedBy`, so the preference a supporter
-- sets is the VenueApproved one -- which is the whole point of the deferral.
insert into public.notification_settings (scholar, event, enabled)
values (:'muted', 'VenueApproved', false);

-- ---- Authorization ---------------------------------------------------------------

select tests.authenticate_as(:'other');
select throws_ok (
	$$ select public.decline_venue_proposal('00000000-0000-4000-8000-0000000000c1', 's', 'm') $$,
	'Only stewards can decline venue proposals',
	'1. a non-steward cannot decline a proposal'
);

-- ---- The decline ------------------------------------------------------------------

select tests.authenticate_as(:'steward');

select lives_ok (
	$$ select public.decline_venue_proposal('00000000-0000-4000-8000-0000000000c1',
	                                        'A venue proposal was not taken forward',
	                                        'The proposal to bring "Journal of Declines" ...') $$,
	'2. a steward can decline a proposal'
);

select is (
	(select count(*)::int from public.proposals
	 where id = '00000000-0000-4000-8000-0000000000c1'), 0,
	'3. the proposal is closed'
);

select is (
	(select count(*)::int from public.emails where event = 'ProposalDeclined'), 3,
	'4. three notices: two supporters, one editor address — not four'
);

select is (
	(select count(*)::int from public.emails
	 where event = 'ProposalDeclined' and scholar = :'supporter'), 1,
	'5. the supporter is told'
);

select is (
	(select count(*)::int from public.emails
	 where event = 'ProposalDeclined' and scholar = :'muted'), 0,
	'6. the supporter who silenced the outcome preference is not'
);

-- Back to owner context: notification_allowed is revoked from `authenticated`, since it
-- reads tables that are deny-all to clients and would otherwise publish whose mute list says
-- what, one probe at a time.
select tests.clear_authentication();

-- The deferral again, from the other side: `muted` set VenueApproved, and it governed a
-- template that is not VenueApproved.
select is (
	public.notification_allowed(:'muted', 'ProposalDeclined'), false,
	'7. because ProposalDeclined defers to the VenueApproved preference'
);

select is (
	(select count(*)::int from public.emails
	 where event = 'ProposalDeclined' and email = 'nc_editor@test.local' and scholar is null), 1,
	'8. a listed editor with no account is written to by address'
);

select is (
	(select count(*)::int from public.emails
	 where event = 'ProposalDeclined' and email = 'nc_both@test.local'), 1,
	'9. and somebody who is both a supporter and a listed editor gets one message'
);

-- ---- The replaced address -----------------------------------------------------------

select tests.create_scholar('nc_first@test.local') as fresh \gset
-- A scholar verifying for the FIRST time has no previous address to write to. The helper
-- gives every scholar an address, so it is cleared to reproduce that state.
update public.scholars set email = null where id = :'fresh';

insert into public.email_verifications (scholar, candidate_email, token_hash, expires_at)
values (:'fresh', 'nc_first_new@test.local',
        encode(extensions.digest('nc-token-first','sha256'),'hex'), now() + interval '1 hour');

select is (
	public.verify_email('nc-token-first') ->> 'status', 'verified',
	'10. a first-ever verification succeeds'
);

select is (
	(select count(*)::int from public.emails where event = 'EmailChanged'), 0,
	'11. and writes to nobody, because there is no address being replaced'
);

-- Now a genuine change.
insert into public.email_verifications (scholar, candidate_email, token_hash, expires_at)
values (:'fresh', 'nc_second@test.local',
        encode(extensions.digest('nc-token-second','sha256'),'hex'), now() + interval '1 hour')
on conflict (scholar) do update set candidate_email = excluded.candidate_email,
	token_hash = excluded.token_hash, expires_at = excluded.expires_at, verified_at = null;

select public.verify_email('nc-token-second');

select results_eq (
	$$ select email, args->>0 from public.emails where event = 'EmailChanged' $$,
	$$ values ('nc_first_new@test.local'::text, 'nc_second@test.local'::text) $$,
	'12. the address being replaced is written to, and told what replaced it'
);

-- Idempotence. The link may be fetched again by a mail scanner or a hover-preload, and the
-- early return on verified_at is what keeps that from sending a second alarming notice.
select public.verify_email('nc-token-second');

select is (
	(select count(*)::int from public.emails where event = 'EmailChanged'), 1,
	'13. and a re-fetch of the same link does not write again'
);

-- ---- Seated directly by an administrator -----------------------------------------------
-- The path that told nobody: _notify_new_volunteer is suppressed for it (an admin's own act
-- is not news to the admins) and RoleInvite only fires where there IS an invitation.

select tests.create_scholar('nc_vadmin@test.local') as vadmin \gset
select tests.create_scholar('nc_seated@test.local') as seated \gset
select tests.create_currency(array[:'vadmin']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'vadmin']::uuid[]) as ven \gset
select tests.create_role(:'ven', 1) as rev \gset

select tests.authenticate_as(:'vadmin');
select lives_ok (
	format($$ select public.create_volunteer(%L::uuid, %L::uuid, true, false, null) $$,
	       :'seated', :'rev'),
	'14. an admin can seat a scholar in a role directly'
);
select tests.clear_authentication();

select is (
	(select count(*)::int from public.emails
	 where event = 'RoleEnrolled' and scholar = :'seated'), 1,
	'15. and the scholar is told they now hold it'
);

-- Consequential: a role with obligations, arriving unasked. There is no preference to consult,
-- which the foreign key enforces rather than leaving to whoever writes the next producer.
select throws_ok (
	format($$ insert into public.notification_settings (scholar, event, enabled)
	          values (%L::uuid, 'RoleEnrolled', false) $$, :'seated'),
	'23503',
	null,
	'16. and cannot switch it off'
);

select * from finish ();
rollback;
