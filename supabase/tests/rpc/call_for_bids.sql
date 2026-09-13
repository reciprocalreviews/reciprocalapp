-- RPC tests for the call for bids: public.queue_call_for_bids and
-- public.call_for_bids_status.
--
-- This is the only mail RR sends whose prose a person writes, so the things under test are
-- the ones that keep that from being a way to mail anybody anything:
--   WHO MAY   venue admins and the holders of the venue's priority-0 role, and nobody else --
--             not a volunteer of the role being written to, not a volunteer of the top role
--             who never accepted, not a signed-in stranger.
--   WHICH     biddable roles only. A nudge to bid, sent to people the submissions page will
--             not show bid buttons to, is a message nobody can act on.
--   WHO GETS  active, accepted volunteers of that role with a verified contact address who
--             have not silenced the notice -- and never the sender themselves.
--   SHAPE     one row PER RECIPIENT (never a cc'd thread, unlike the new-volunteer notice),
--             reply_to the sender's own address, subject and message null so the body is
--             rendered from the registry, and six args none of which is JSON null.
--   BOUNDS    a note must be non-empty after trimming and at most 1000 characters.
--
-- Inserting an email fires the send_on_email_insert AFTER trigger (net.http_post via the
-- `supabase_url` vault secret). The RLS CI job doesn't set that env, so the URL is null and
-- the post raises. Nothing here depends on mail actually being dispatched, so the trigger is
-- disabled for this rolled-back test, exactly as new_volunteer_notice.sql does.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan (29);

alter table public.emails disable trigger send_on_email_insert;

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('cfb_minter@test.local')  as minter  \gset
select tests.create_scholar('cfb_admin@test.local')   as admin   \gset
select tests.create_scholar('cfb_editor@test.local')  as editor  \gset
select tests.create_scholar('cfb_r1@test.local')      as r1      \gset
select tests.create_scholar('cfb_r2@test.local')      as r2      \gset
select tests.create_scholar('cfb_muted@test.local')   as muted   \gset
select tests.create_scholar('cfb_noaddr@test.local')  as noaddr  \gset
select tests.create_scholar('cfb_paused@test.local')  as paused  \gset
select tests.create_scholar('cfb_pending@test.local') as pending \gset
select tests.create_scholar('cfb_stranger@test.local') as stranger \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

-- The priority-0 role, named something OTHER than "Editor": the message reports the venue's
-- own word for the sender's job rather than assuming one.
select tests.create_role(:'ven', 0, null, false, true) as toprole \gset
update public.roles set name = 'Area Chair' where id = :'toprole';
select tests.create_volunteer(:'editor', :'toprole') as ed_vol \gset

-- The biddable role being written to.
select tests.create_role(:'ven', 1, null, true, false) as bidrole \gset
update public.roles set name = 'Reviewer' where id = :'bidrole';

-- A non-biddable role at the same venue, for the negative case.
select tests.create_role(:'ven', 2, null, false, false) as quietrole \gset

-- The volunteers. r1 and r2 should receive; the rest are each excluded for one reason.
select tests.create_volunteer(:'r1', :'bidrole')                as v_r1      \gset
select tests.create_volunteer(:'r2', :'bidrole')                as v_r2      \gset
select tests.create_volunteer(:'muted', :'bidrole')             as v_muted   \gset
select tests.create_volunteer(:'noaddr', :'bidrole')            as v_noaddr  \gset
select tests.create_volunteer(:'paused', :'bidrole')            as v_paused  \gset
select tests.create_volunteer(:'pending', :'bidrole', 'invited') as v_pending \gset

-- The sender is also a volunteer of the role they are writing to. Someone can hold the top
-- role and still review; telling them their own news is noise.
select tests.create_volunteer(:'editor', :'bidrole') as v_editor \gset

update public.volunteers set active = false where id = :'v_paused';
update public.scholars set email = null where id = :'noaddr';
insert into public.notification_settings (scholar, event, enabled)
values (:'muted', 'CallForBids', false);

-- ---- Authorization -------------------------------------------------------------

select tests.authenticate_as(:'r1');
select throws_ok(
	format('select public.queue_call_for_bids(%L, %L)', :'bidrole', 'let me in'),
	'You are not authorized to write to this venue''s volunteers',
	'a volunteer of the role cannot write to it'
);

select tests.authenticate_as(:'stranger');
select throws_ok(
	format('select public.queue_call_for_bids(%L, %L)', :'bidrole', 'hello'),
	'You are not authorized to write to this venue''s volunteers',
	'a signed-in stranger cannot write to a venue''s volunteers'
);

-- Anon never reaches the `auth.uid() is null` check inside the function: EXECUTE is revoked
-- from anon outright, so the refusal is a permission denial at plan time. That is the
-- stronger of the two guards, and it is the one that must not regress -- Supabase's default
-- privileges re-grant EXECUTE to anon on every `create or replace`, so the revoke has to
-- travel in the same migration as the function.
select tests.authenticate_as_anon();
select throws_ok(
	format('select public.queue_call_for_bids(%L, %L)', :'bidrole', 'hello'),
	'42501',
	'permission denied for function queue_call_for_bids',
	'an anonymous caller cannot execute the function at all'
);

-- ---- The note's bounds ---------------------------------------------------------

select tests.authenticate_as(:'editor');
select throws_ok(
	format('select public.queue_call_for_bids(%L, %L)', :'bidrole', '   '),
	'A call for bids cannot be empty',
	'a note of only whitespace is empty'
);
select throws_ok(
	format('select public.queue_call_for_bids(%L, %L)', :'bidrole', repeat('a', 1001)),
	'A call for bids must be at most 1000 characters',
	'a note past 1000 characters is refused'
);

-- ---- Which roles can be written to ---------------------------------------------

select throws_ok(
	format('select public.queue_call_for_bids(%L, %L)', :'quietrole', 'please bid'),
	'Bidding is not enabled for this role',
	'a non-biddable role cannot be asked to bid'
);

select throws_ok(
	format('select public.queue_call_for_bids(%L, %L)', gen_random_uuid(), 'please bid'),
	'Role not found',
	'a role that does not exist is reported as such'
);

-- ---- The sender needs a reply path ---------------------------------------------
--
-- The whole point of this notice is that a person is asking, and Reply-To is resolved to the
-- sender's own address. An editor with no verified address would be sending a personal letter
-- nobody can answer, so the send is refused rather than quietly falling back to stewards@.

select tests.clear_authentication();
update public.scholars set email = null where id = :'editor';
select tests.authenticate_as(:'editor');
select throws_ok(
	format('select public.queue_call_for_bids(%L, %L)', :'bidrole', 'please bid'),
	'A call for bids replies to you, so it needs a verified contact address',
	'a sender with no verified address is refused'
);
select tests.clear_authentication();
update public.scholars set email = 'cfb_editor@test.local' where id = :'editor';

-- ---- The happy path ------------------------------------------------------------

select tests.authenticate_as(:'editor');
select lives_ok(
	format('select public.queue_call_for_bids(%L, %L)', :'bidrole', '  We are short on reviews.  '),
	'a priority-0 holder may ask a biddable role to bid'
);

select is(
	(select count(*)::integer from public.emails where event = 'CallForBids'),
	2,
	'exactly the two eligible volunteers were written to'
);

select results_eq(
	$$select email from public.emails where event = 'CallForBids' order by email$$,
	$$values ('cfb_r1@test.local'), ('cfb_r2@test.local')$$,
	'the muted, unverified, paused, pending volunteers and the sender are all skipped'
);

-- One row PER RECIPIENT. NewVolunteer uses cc because a welcome should converge into one
-- thread; the opposite is true here -- these are reviewers who must not learn each other's
-- addresses, and a biddable role routinely holds more than the 50 Resend accepts on a send.
select is(
	(select count(*)::integer from public.emails where event = 'CallForBids' and cc is not null),
	0,
	'nobody is cc''d: these are private copies, not one shared thread'
);

select is(
	(select count(distinct reply_to)::integer from public.emails where event = 'CallForBids'),
	1,
	'every copy replies to the same place'
);
select is(
	(select distinct reply_to from public.emails where event = 'CallForBids'),
	'cfb_editor@test.local',
	'replies reach the editor who wrote it, not the steward inbox'
);

select is(
	(select count(*)::integer from public.emails
	 where event = 'CallForBids' and (subject is not null or message is not null)),
	0,
	'subject and message are null, so the body is rendered from the registry at send time'
);

select is(
	(select count(distinct sender)::integer from public.emails where event = 'CallForBids'),
	1,
	'the sender is recorded on every copy, so the mail is attributable'
);

select is(
	(select count(*)::integer from public.emails where event = 'CallForBids' and venue = :'ven'),
	2,
	'the rows carry the venue, which is what the status function reads'
);

-- ---- The arguments -------------------------------------------------------------
--
-- EVERY element must be non-null. The edge function validates args as z.array(z.string()), so
-- one JSON null makes the whole body fail to parse, the function answers 400, and pg_net
-- swallows it -- the mail never arrives, with nothing on screen to say so.

select is(
	(select jsonb_array_length(args) from public.emails where event = 'CallForBids' limit 1),
	6,
	'six arguments, as the CallForBids template expects'
);

select is(
	(select count(*)::integer from public.emails e, jsonb_array_elements(e.args) a
	 where e.event = 'CallForBids' and jsonb_typeof(a) <> 'string'),
	0,
	'no argument is JSON null, which would make the whole send fail silently'
);

select is(
	(select args->>2 from public.emails where event = 'CallForBids' limit 1),
	'Area Chair',
	'the sender is described by the venue''s own word for its top role, not a fixed title'
);

select is(
	(select args->>3 from public.emails where event = 'CallForBids' limit 1),
	'We are short on reviews.',
	'the note is stored trimmed, as one argument rather than a body'
);

select is(
	(select args->>4 from public.emails where event = 'CallForBids' limit 1),
	'Reviewer',
	'the recipient is told which role they are being written to about'
);

-- ---- Status ---------------------------------------------------------------------

select is(
	((select public.call_for_bids_status(:'bidrole'))->>'eligible')::integer,
	2,
	'the status reports the same count the send reached, not the role''s volunteer count'
);

select is(
	(select public.call_for_bids_status(:'bidrole'))->>'last_sender',
	(select name from public.scholars where id = :'editor'),
	'the status names who last asked, so a co-chair can see it was already done'
);

select isnt(
	(select public.call_for_bids_status(:'bidrole'))->'last_sent',
	'null'::jsonb,
	'the status records when the venue last asked'
);

select tests.authenticate_as(:'r1');
select throws_ok(
	format('select public.call_for_bids_status(%L)', :'bidrole'),
	'You are not authorized to read this venue''s call for bids',
	'the status is gated the same way the send is: it discloses the venue''s mail log'
);

-- ---- A venue admin who holds no role --------------------------------------------
--
-- Admins run the venue, so excluding them would mean an admin who holds no role cannot write
-- to their own community. Their label falls back to the generic word, since there is no role
-- name to borrow.

select tests.authenticate_as(:'admin');
select lives_ok(
	format('select public.queue_call_for_bids(%L, %L)', :'bidrole', 'please take a look'),
	'a venue admin who holds no role may also ask'
);

select is(
	(select args->>2 from public.emails
	 where event = 'CallForBids' and sender = :'admin' limit 1),
	'an administrator',
	'an admin with no role is described generically rather than borrowing a role name'
);

-- There is deliberately NO rate limit: an editor decides when their community needs asking.
-- The second send above went out moments after the first, and both are recorded.
-- Five, not four: the admin's send also reaches the EDITOR, who is an active, accepted
-- volunteer of the biddable role. Only the sender is excluded from their own call, and the
-- admin is not one of its volunteers.
select is(
	(select count(*)::integer from public.emails where event = 'CallForBids'),
	5,
	'a second call for bids is not rate limited, and only the sender is left off their own'
);

select * from finish ();
rollback;
