-- RPC tests for the new-volunteer notice: public._notify_new_volunteer, and the branch of
-- public.create_volunteer that calls it.
--
-- What is under test:
--   WHO      the holders of the venue's priority-0 role -- active, accepted, with a
--            verified contact address, who have not silenced the notice, and never the new
--            volunteer themselves. Venue admins are deliberately NOT included.
--   WHEN     only a scholar volunteering for THEMSELVES for an OPEN role. Not an admin
--            adding someone, not an invitation being accepted, not an invite-only role.
--   SHAPE    exactly ONE emails row per event: the longest-standing holder in `email`, the
--            rest in `cc`, and the volunteer's own address in `reply_to`, so the notice is
--            one shared thread whose Reply reaches the newcomer.
--   ARGS     six elements, none of them JSON null -- see the note on test 7, which is the
--            failure mode that would otherwise be silent.
--
-- Inserting an email fires the send_on_email_insert AFTER trigger (net.http_post via the
-- `supabase_url` vault secret). The RLS CI job doesn't set that env, so the URL is null and
-- the post raises. None of this depends on the mail actually being dispatched, so the
-- trigger is disabled for this rolled-back test, exactly as emails_rls.sql does.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan (22);

alter table public.emails disable trigger send_on_email_insert;

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

-- Venue A: the main scenario. A priority-0 role with several holders, and an open role for
-- newcomers to join.
select tests.create_scholar('nv_minter@test.local')    as minter    \gset
select tests.create_scholar('nv_admin@test.local')     as admin     \gset
select tests.create_scholar('nv_hold1@test.local')     as hold1     \gset
select tests.create_scholar('nv_hold2@test.local')     as hold2     \gset
select tests.create_scholar('nv_hold3@test.local')     as hold3     \gset
select tests.create_scholar('nv_muted@test.local')     as muted     \gset
select tests.create_scholar('nv_noaddr@test.local')    as noaddr    \gset
select tests.create_scholar('nv_paused@test.local')    as paused    \gset
select tests.create_scholar('nv_pending@test.local')   as pending   \gset
select tests.create_scholar('nv_newbie@test.local')    as newbie    \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

-- The priority-0 role, named something OTHER than "Editor". The notice must report the
-- venue's own word for the role rather than assuming one.
select tests.create_role(:'ven', 0, null, false, true) as toprole \gset
update public.roles set name = 'Area Chair' where id = :'toprole';

-- The open role a newcomer can join.
select tests.create_role(:'ven', 1, null, false, false) as openrole \gset
update public.roles set name = 'Reviewer' where id = :'openrole';

-- An invite-only role, for the negative case.
select tests.create_role(:'ven', 2, null, false, true) as shutrole \gset

-- The holders. created_at is staggered explicitly: the To slot is decided by how long
-- someone has held the role, and every fixture row would otherwise share a timestamp.
select tests.create_volunteer(:'hold1', :'toprole') as v1 \gset
select tests.create_volunteer(:'hold2', :'toprole') as v2 \gset
select tests.create_volunteer(:'hold3', :'toprole') as v3 \gset
update public.volunteers set created_at = '2020-01-01' where id = :'v1';
update public.volunteers set created_at = '2021-01-01' where id = :'v2';
update public.volunteers set created_at = '2022-01-01' where id = :'v3';

-- Four holders who must NOT be written to, each for a different reason.
select tests.create_volunteer(:'muted', :'toprole')   as vm \gset
select tests.create_volunteer(:'noaddr', :'toprole')  as vn \gset
select tests.create_volunteer(:'paused', :'toprole')  as vp \gset
select tests.create_volunteer(:'pending', :'toprole', 'invited') as vi \gset
insert into public.notification_settings (scholar, event, enabled)
values (:'muted', 'NewVolunteer', false);
update public.scholars set email = null where id = :'noaddr';
update public.volunteers set active = false where id = :'vp';

-- ---- The notice --------------------------------------------------------------
select tests.authenticate_as(:'newbie');
select lives_ok(
	format($$ select public.create_volunteer(%L::uuid, %L::uuid, true, true, null) $$, :'newbie', :'openrole'),
	'a scholar can volunteer for an open role'
);
select tests.clear_authentication();

select is(
	(select count(*)::int from public.emails where event = 'NewVolunteer' and venue = :'ven'),
	1,
	'volunteering for an open role queues exactly one notice'
);

-- ONE row, not one per holder: that is what makes it a single shared thread instead of
-- three private ones that never see each other.
select is(
	(select email from public.emails where event = 'NewVolunteer' and venue = :'ven'),
	'nv_hold1@test.local',
	'the longest-standing holder of the priority-0 role is the addressee'
);

select is(
	(select cc from public.emails where event = 'NewVolunteer' and venue = :'ven'),
	array['nv_hold2@test.local', 'nv_hold3@test.local'],
	'the remaining holders are copied, in order of how long they have held the role'
);

-- The whole point of the feature: Reply reaches the newcomer, not the stewards.
select is(
	(select reply_to from public.emails where event = 'NewVolunteer' and venue = :'ven'),
	'nv_newbie@test.local',
	'the notice replies to the new volunteer'
);

select is(
	(select jsonb_array_length(args) from public.emails where event = 'NewVolunteer' and venue = :'ven'),
	6,
	'the notice carries all six template arguments'
);

-- The silent failure this guards against: jsonb_build_array with a NULL element yields
-- JSON null, the edge function validates args as z.array(z.string()) and rejects the WHOLE
-- body, it answers 400, and pg_net swallows it -- so the email never arrives and nothing
-- says so. scholars.name is nullable and role and venue titles default to '', so every one
-- of them is coalesced at the source.
select is(
	(select count(*)::int from public.emails m, jsonb_array_elements(m.args) a
	 where m.event = 'NewVolunteer' and m.venue = :'ven' and jsonb_typeof(a) <> 'string'),
	0,
	'every template argument is a string, so the edge function can parse the body'
);

-- The venue's word for its top role, not a hardcoded "Editor".
select is(
	(select args ->> 5 from public.emails where event = 'NewVolunteer' and venue = :'ven'),
	'Area Chair',
	'the notice names the priority-0 role as the venue named it'
);

select is(
	(select args ->> 1 from public.emails where event = 'NewVolunteer' and venue = :'ven'),
	'Reviewer',
	'the notice names the role that was volunteered for'
);

-- ---- Who is left out, and why -------------------------------------------------
select is(
	(select count(*)::int from public.emails
	 where event = 'NewVolunteer' and venue = :'ven'
	   and ('nv_muted@test.local' = any (cc) or email = 'nv_muted@test.local')),
	0,
	'a holder who silenced the notice is neither addressed nor copied'
);

select is(
	(select count(*)::int from public.emails
	 where event = 'NewVolunteer' and venue = :'ven'
	   and ('nv_paused@test.local' = any (cc) or email = 'nv_paused@test.local')),
	0,
	'a holder who has stopped volunteering is not written to'
);

select is(
	(select count(*)::int from public.emails
	 where event = 'NewVolunteer' and venue = :'ven'
	   and ('nv_pending@test.local' = any (cc) or email = 'nv_pending@test.local')),
	0,
	'a holder who has not accepted their invitation is not written to'
);

-- A holder with no verified address is skipped rather than written to as null: scholars.email
-- holds only verified addresses, so null means "we may not mail this person at all".
select is(
	(select cardinality(cc) + 1 from public.emails where event = 'NewVolunteer' and venue = :'ven'),
	3,
	'only the three reachable, opted-in holders are on the message'
);

-- ---- Venue B: a lone holder, and the volunteer who is one ---------------------
select tests.create_scholar('nv_b_minter@test.local') as bminter \gset
select tests.create_scholar('nv_b_admin@test.local')  as badmin  \gset
select tests.create_scholar('nv_b_hold@test.local')   as bhold   \gset
select tests.create_scholar('nv_b_new@test.local')    as bnew    \gset
select tests.create_currency(array[:'bminter']::uuid[]) as bcur \gset
select tests.create_venue(:'bcur', array[:'badmin']::uuid[]) as bven \gset
select tests.create_role(:'bven', 0, null, false, true)  as btop  \gset
select tests.create_role(:'bven', 1, null, false, false) as bopen \gset
select tests.create_volunteer(:'bhold', :'btop') as bv \gset

select tests.authenticate_as(:'bnew');
select public.create_volunteer(:'bnew'::uuid, :'bopen'::uuid, true, true, null);
select tests.clear_authentication();

-- A single holder must leave cc NULL, not an empty array: `cc: []` is a malformed field to
-- Resend, and the emails_cc_shape constraint forbids storing one at all.
select is(
	(select cc from public.emails where event = 'NewVolunteer' and venue = :'bven'),
	null,
	'a venue with one holder sends no Cc at all'
);

-- The holder volunteering for a second role at their own venue is their own news.
select tests.authenticate_as(:'bhold');
select public.create_volunteer(:'bhold'::uuid, :'bopen'::uuid, true, true, null);
select tests.clear_authentication();

select is(
	(select count(*)::int from public.emails where event = 'NewVolunteer' and venue = :'bven'),
	1,
	'a holder volunteering at their own venue is not told about themselves'
);

-- ---- A volunteer with no verified address ------------------------------------
select tests.create_scholar('nv_b_quiet@test.local') as bquiet \gset
update public.scholars set email = null where id = :'bquiet';
select tests.authenticate_as(:'bquiet');
select public.create_volunteer(:'bquiet'::uuid, :'bopen'::uuid, true, true, null);
select tests.clear_authentication();

-- The notice still goes out: the news is what matters, and a scholar with no contact
-- address is precisely the one a holder needs the profile link for. The null reply_to is
-- what makes the branded footer fall back to naming the stewards.
select is(
	(select count(*)::int from public.emails
	 where event = 'NewVolunteer' and venue = :'bven' and reply_to is null),
	1,
	'a volunteer with no verified address is still announced, with no reply path'
);

-- ---- The three ways this must stay silent ------------------------------------
select tests.create_scholar('nv_added@test.local') as added \gset
select tests.authenticate_as(:'admin');
select public.create_volunteer(:'added'::uuid, :'openrole'::uuid, true, false, null);
select tests.clear_authentication();

select is(
	(select count(*)::int from public.emails where event = 'NewVolunteer' and venue = :'ven'),
	1,
	'an admin adding a volunteer is that admin''s own action, and announces nothing'
);

-- An invitation is answered through accept_role_invite, which stays silent because the
-- people who would be told are the ones who sent it.
select tests.create_scholar('nv_invitee@test.local') as invitee \gset
select tests.authenticate_as(:'admin');
select public.create_volunteer(:'invitee'::uuid, :'shutrole'::uuid, false, false, null);
select tests.clear_authentication();
select id as inviterow from public.volunteers where scholarid = :'invitee' and roleid = :'shutrole' \gset
select tests.authenticate_as(:'invitee');
select public.accept_role_invite(:'inviterow'::uuid, 'accepted');
select tests.clear_authentication();

select is(
	(select count(*)::int from public.emails where event = 'NewVolunteer' and venue = :'ven'),
	1,
	'accepting a role invitation announces nothing'
);

select tests.create_scholar('nv_intruder@test.local') as intruder \gset
select tests.authenticate_as(:'intruder');
select throws_ok(
	format($$ select public.create_volunteer(%L::uuid, %L::uuid, true, true, null) $$, :'intruder', :'shutrole'),
	'You are not authorized to volunteer for this role',
	'an invite-only role cannot be self-volunteered for, so nothing is announced'
);
select tests.clear_authentication();

-- ---- Venue C: no priority-0 role ----------------------------------------------
-- Volunteering must still succeed. A venue with nobody to tell is a venue configuration
-- problem, not a failure of volunteering.
select tests.create_scholar('nv_c_minter@test.local') as cminter \gset
select tests.create_scholar('nv_c_admin@test.local')  as cadmin  \gset
select tests.create_scholar('nv_c_new@test.local')    as cnew    \gset
select tests.create_currency(array[:'cminter']::uuid[]) as ccur \gset
select tests.create_venue(:'ccur', array[:'cadmin']::uuid[]) as cven \gset
select tests.create_role(:'cven', 3, null, false, false) as copen \gset

select tests.authenticate_as(:'cnew');
select lives_ok(
	format($$ select public.create_volunteer(%L::uuid, %L::uuid, true, true, null) $$, :'cnew', :'copen'),
	'a venue with no priority-0 role can still be volunteered for'
);
select tests.clear_authentication();

select is(
	(select count(*)::int from public.emails where event = 'NewVolunteer' and venue = :'cven'),
	0,
	'a venue with nobody to tell announces nothing'
);

-- ---- The helper is not an entry point ----------------------------------------
-- Its authorization IS create_volunteer's: there is no way to ask for this mail without
-- also becoming a volunteer, and RR004 makes that a once-per-(scholar, role) event forever.
-- Granting it directly would hand out a way to send branded mail on demand.
select ok(
	not has_function_privilege('authenticated', 'public._notify_new_volunteer(uuid,uuid,uuid)', 'execute'),
	'the fan-out helper is not callable by authenticated'
);

select * from finish();
rollback;
