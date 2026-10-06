-- RPC tests for the weekly bidding digest: public.bidding_digest_candidates,
-- private.expertise_keys and public.queue_bidding_digest.
--
--   WHO      available volunteers of a biddable role, with a verified address, who have not
--            silenced BiddingDigest -- and nobody paused, pending, unavailable or muted.
--   WHAT     submissions still under review at an active venue, with bidding not closed by
--            their editor, whose role wants more people than it has approved -- never one the scholar wrote, declared a conflict on, or
--            already holds any assignment on.
--   ORDER    most people missing first, then the closer expertise match, then oldest; capped,
--            with the rest counted.
--   ONCE     a list is fingerprinted by its (submission, role) set, and neither the candidates
--            function nor queue_bidding_digest offers the same list twice, or any list inside
--            the interval; a scholar found to have nothing new is stamped and passed over.
--   FAIR     whoever has waited longest comes first, so a Monday too big to finish reaches the
--            rest first next week; and after the last run the stewards are told who was missed.
--   WHO MAY  the service role alone.
--
-- The send_on_email_insert trigger is disabled, as in call_for_bids.sql: nothing here depends
-- on mail being dispatched, and the RLS CI job has no `supabase_url` secret to post to.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan (42);

alter table public.emails disable trigger send_on_email_insert;

-- The titles a scholar's digest lists, in order, across groups.
create function pg_temp.titles (_scholar uuid, _cap integer default 7) returns text[] language sql as $$
	select array_agg(item->>'title' order by g.o, i.o)
	from public.bidding_digest_candidates (200, _cap) c,
		jsonb_array_elements(c.digest->'groups') with ordinality g (grp, o),
		jsonb_array_elements(g.grp->'items') with ordinality i (item, o)
	where c.scholar = _scholar;
$$;

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('bd_minter@test.local')  as minter  \gset
select tests.create_scholar('bd_admin@test.local')   as admin   \gset
select tests.create_scholar('bd_author@test.local')  as author  \gset
select tests.create_scholar('bd_rev@test.local')     as rev     \gset
select tests.create_scholar('bd_away@test.local')    as away    \gset
select tests.create_scholar('bd_noaddr@test.local')  as noaddr  \gset
select tests.create_scholar('bd_muted@test.local')   as muted   \gset
select tests.create_scholar('bd_paused@test.local')  as paused  \gset
select tests.create_scholar('bd_pending@test.local') as pending \gset
select tests.create_scholar('bd_quiet@test.local')   as quiet   \gset
select tests.create_scholar('bd_other@test.local')   as other   \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset
select tests.create_submission_type(:'ven') as stype \gset

-- The biddable role wants two people per submission.
select tests.create_role(:'ven', 1, null, true, false) as bidrole \gset
update public.roles set name = 'Reviewer', desired_assignments = 2 where id = :'bidrole';
-- A role nobody bids on.
select tests.create_role(:'ven', 0, null, false, true) as quietrole \gset

select tests.create_volunteer(:'rev', :'bidrole') as v_rev \gset
select tests.create_volunteer(:'away', :'bidrole') as v_away \gset
select tests.create_volunteer(:'noaddr', :'bidrole') as v_noaddr \gset
select tests.create_volunteer(:'muted', :'bidrole') as v_muted \gset
select tests.create_volunteer(:'paused', :'bidrole') as v_paused \gset
select tests.create_volunteer(:'pending', :'bidrole', 'invited') as v_pending \gset
select tests.create_volunteer(:'quiet', :'quietrole') as v_quiet \gset
select tests.create_volunteer(:'other', :'bidrole') as v_other \gset
update public.volunteers set expertise = 'peer review, STATISTICS ' where id = :'v_rev';

update public.scholars set available = false where id = :'away';
update public.scholars set email = null where id = :'noaddr';
update public.volunteers set active = false where id = :'v_paused';
insert into public.notification_settings (scholar, event, enabled) values (:'muted', 'BiddingDigest', false);

-- The submissions, each testing one rule for `rev`.
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_open     \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_open2    \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_open3    \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_partial  \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_full     \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_done     \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_conflict \gset
select tests.create_submission(:'ven', :'stype', array[:'rev']::uuid[])    as s_authored \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_bid      \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_seated   \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_closed   \gset

-- Missing 2, matching, newest of the three: the match outranks age.
update public.submissions set title = 'Open', expertise = ' Statistics , sampling,statistics',
	created_at = now() - interval '1 day' where id = :'s_open';
-- Missing 2, no match; oldest, then newer.
update public.submissions set title = 'Open two', created_at = now() - interval '3 days' where id = :'s_open2';
update public.submissions set title = 'Open three', created_at = now() - interval '2 days' where id = :'s_open3';
-- Missing 1: one of two seats taken, and a pending bid that does NOT count towards it.
update public.submissions set title = 'Partial', expertise = 'statistics', created_at = now() - interval '9 days' where id = :'s_partial';
select tests.create_assignment(:'ven', :'s_partial', :'author', :'bidrole') \gset
select tests.create_assignment(:'ven', :'s_partial', :'other', :'bidrole', false, true) \gset
-- Excluded, one rule each.
update public.submissions set title = 'Full' where id = :'s_full';
select tests.create_assignment(:'ven', :'s_full', :'author', :'bidrole') \gset
select tests.create_assignment(:'ven', :'s_full', :'other', :'bidrole') \gset
update public.submissions set title = 'Done', status = 'done' where id = :'s_done';
update public.submissions set title = 'Conflicted' where id = :'s_conflict';
insert into public.conflicts (submissionid, scholarid) values (:'s_conflict', :'rev');
update public.submissions set title = 'Authored' where id = :'s_authored';
update public.submissions set title = 'Already bid' where id = :'s_bid';
select tests.create_assignment(:'ven', :'s_bid', :'rev', :'bidrole', false, true) \gset
-- Seated in ANOTHER role on it: still excluded.
update public.submissions set title = 'Seated' where id = :'s_seated';
select tests.create_assignment(:'ven', :'s_seated', :'rev', :'quietrole') \gset
-- Seats open, but its editor has closed bidding on it.
alter table public.submissions disable trigger enforce_submission_author_edits;
update public.submissions set title = 'Bidding closed', bidding_closed = true where id = :'s_closed';
alter table public.submissions enable trigger enforce_submission_author_edits;

-- A switched-off venue whose open submission must never appear.
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as offven \gset
select tests.create_submission_type(:'offven') as offtype \gset
select tests.create_role(:'offven', 1, null, true, false) as offrole \gset
select tests.create_volunteer(:'rev', :'offrole') \gset
select tests.create_submission(:'offven', :'offtype', array[:'author']::uuid[]) as s_off \gset
update public.submissions set title = 'Switched off' where id = :'s_off';
update public.venues set inactive = 'Closed for the summer.' where id = :'offven';

-- ---- The keyword rule ------------------------------------------------------------
-- The same cases src/email/biddingDigest.unit.ts puts to expertiseTags.

select is (
	(select array_agg(label order by ord) from private.expertise_keys (' Peer Review ,, statistics ,')),
	array['Peer Review', 'statistics'],
	'expertise splits on commas, trims, and drops empties'
);

select is (
	(select array_agg(key order by ord) from private.expertise_keys ('Peer Review')),
	array['peer review'],
	'expertise matches without regard to case'
);

select is_empty (
	'select 1 from private.expertise_keys (null)',
	'no expertise is no keywords'
);

-- ---- What is offered, in what order -------------------------------------------------

select is (
	pg_temp.titles (:'rev'),
	array['Open', 'Open two', 'Open three', 'Partial'],
	'need first, then match, then oldest; and nothing full, done, conflicted, authored, bid, seated, closed to bidding or switched off'
);

select is (
	(select total from public.bidding_digest_candidates () where scholar = :'rev'),
	4,
	'the total counts every submission offered'
);

select is (
	(select c.digest->'groups'->0->'items'->0->'matches' from public.bidding_digest_candidates () c where c.scholar = :'rev'),
	'["Statistics"]'::jsonb,
	'a match is named once, in the submission''s spelling'
);

select is (
	pg_temp.titles (:'rev', 2),
	array['Open', 'Open two'],
	'the cap keeps the top of the list'
);

select is (
	(select (c.digest->'groups'->0->>'more')::int from public.bidding_digest_candidates (200, 2) c where c.scholar = :'rev'),
	2,
	'and counts the rest'
);

select is (
	(select (c.digest->'groups'->0) - 'items' - 'more' from public.bidding_digest_candidates () c where c.scholar = :'rev'),
	jsonb_build_object('venue', 'Test Venue', 'path', :'ven'::text, 'role', 'Reviewer'),
	'a venue with no short title or address is named by its title and reached by its id'
);

update public.venues set short_title = 'TV', slug = 'test-venue' where id = :'ven';
select is (
	(select (c.digest->'groups'->0) - 'items' - 'more' from public.bidding_digest_candidates () c where c.scholar = :'rev'),
	jsonb_build_object('venue', 'TV', 'path', 'test-venue', 'role', 'Reviewer'),
	'a venue with a short title and an address uses both'
);

select is_empty (
	format(
		'select 1 from public.bidding_digest_candidates () where scholar in (%L, %L, %L, %L, %L, %L)',
		:'away', :'noaddr', :'muted', :'paused', :'pending', :'quiet'
	),
	'unavailable, unaddressed, muted, paused, pending and non-bidding volunteers are not candidates'
);

-- ---- The fingerprint -------------------------------------------------------------------

select (select fingerprint from public.bidding_digest_candidates () where scholar = :'rev') as fp1 \gset

select is (
	:'fp1',
	encode(sha256(convert_to((
		select string_agg(p, E'\n' order by p)
		from unnest(array[:'s_open', :'s_open2', :'s_open3', :'s_partial']) s,
			lateral (select s || ':' || :'bidrole' as p) x
	), 'UTF8')), 'hex'),
	'the fingerprint is a SHA-256 of the sorted (submission, role) pairs'
);

-- Someone is seated on Open: it is still open, one person short, so the list is the same.
select tests.create_assignment(:'ven', :'s_open', :'other', :'bidrole') \gset
select is (
	(select fingerprint from public.bidding_digest_candidates () where scholar = :'rev'),
	:'fp1',
	'a change in how many people are missing is not a new list'
);

-- Open three fills: the set changes.
select tests.create_assignment(:'ven', :'s_open3', :'author', :'bidrole') \gset
select tests.create_assignment(:'ven', :'s_open3', :'other', :'bidrole') \gset
select isnt (
	(select fingerprint from public.bidding_digest_candidates () where scholar = :'rev'),
	:'fp1',
	'a submission leaving the list is a new list'
);

select (select fingerprint from public.bidding_digest_candidates () where scholar = :'rev') as fp2 \gset

-- ---- Order and paging ----------------------------------------------------------------------

-- `other` was last sent a digest long ago; `rev` never. Never-sent comes first.
insert into public.bidding_digests (scholar, sent_at, fingerprint)
values (:'other', now() - interval '20 days', repeat('e', 64));

select ok (
	(select min(o) filter (where c.scholar = :'rev') < min(o) filter (where c.scholar = :'other')
	 from public.bidding_digest_candidates (1000) with ordinality as c (scholar, fingerprint, total, digest, o)),
	'a scholar never sent a digest comes before one sent long ago'
);

select is (
	(select count(*)::int from public.bidding_digest_candidates (1)),
	1,
	'a page holds at most the limit'
);

select is (
	public.mark_bidding_digests_checked (array[:'other']::uuid[]),
	1,
	'a scholar with nothing to send can be marked checked'
);

select is_empty (
	format('select 1 from public.bidding_digest_candidates (1000) where scholar = %L', :'other'),
	'and is passed over until the interval has run'
);

select is (
	(select sent_at from public.bidding_digests where scholar = :'other'),
	now() - interval '20 days',
	'marking a scholar checked does not pretend they were sent one'
);

-- ---- Queueing ----------------------------------------------------------------------

select is (
	public.queue_bidding_digest (:'rev', array['{}', '3 submissions'], :'fp2'),
	1,
	'a first digest is queued'
);

select results_eq (
	format('select event, subject, message, args from public.emails where scholar = %L', :'rev'),
	$$ values ('BiddingDigest'::text, null::text, null::text, '["{}", "3 submissions"]'::jsonb) $$,
	'as a BiddingDigest row rendered from its arguments at send time'
);

select is (
	(select fingerprint from public.bidding_digests where scholar = :'rev'),
	:'fp2',
	'and stamped with its fingerprint'
);

select is (
	public.queue_bidding_digest (:'rev', array['{}', 'x'], repeat('b', 64)),
	0,
	'a second digest inside the interval is not queued, even with a new list'
);

select is_empty (
	format('select 1 from public.bidding_digest_candidates () where scholar = %L', :'rev'),
	'a scholar inside the interval is not a candidate'
);

update public.bidding_digests set sent_at = now() - interval '7 days' where scholar = :'rev';

select results_eq (
	format('select fingerprint, digest from public.bidding_digest_candidates () where scholar = %L', :'rev'),
	format('values (%L::text, null::jsonb)', :'fp2'),
	'after the interval an unchanged list is reported, with nothing to send'
);

select is (
	public.queue_bidding_digest (:'rev', array['{}', 'x'], :'fp2'),
	0,
	'and queue_bidding_digest will not send it either'
);

select is (
	public.queue_bidding_digest (:'rev', array['{}', 'x'], repeat('b', 64)),
	1,
	'a changed list is sent'
);

select is (
	(select count(*)::int from public.emails where scholar = :'rev' and event = 'BiddingDigest'),
	2,
	'two digests in all'
);

select throws_ok (
	format('select public.queue_bidding_digest (%L, array[''{}''], %L)', :'rev', 'not-a-hash'),
	'A SHA-256 fingerprint is required',
	'a malformed fingerprint is refused'
);

select is (
	public.queue_bidding_digest (:'muted', array['{}', 'x'], repeat('c', 64)),
	0,
	'a muted scholar is not sent one'
);

select is (
	public.queue_bidding_digest (:'away', array['{}', 'x'], repeat('c', 64)),
	0,
	'an unavailable scholar is not sent one'
);

select is_empty (
	format('select 1 from public.bidding_digests where scholar in (%L, %L)', :'muted', :'away'),
	'and neither is stamped as if they had been'
);

-- Availability is checked again at the send, not only when the list is built: a scholar who
-- switches it off after the page was read is still not written to.
update public.bidding_digests set sent_at = now() - interval '7 days' where scholar = :'rev';
update public.scholars set available = false where id = :'rev';
select is (
	public.queue_bidding_digest (:'rev', array['{}', 'x'], repeat('f', 64)),
	0,
	'a scholar who became unavailable after the list was built is not sent one'
);
update public.scholars set available = true where id = :'rev';

-- ---- The backlog -------------------------------------------------------------------

select is (
	public.report_bidding_digest_backlog (),
	(select count(*)::int from private.bidding_digest_recipients ('6 days')),
	'the backlog counts everyone due a digest who was not reached'
);

select results_eq (
	$$ select event, email, scholar, args->>1 from public.emails where event = 'BiddingDigestBacklog' $$,
	$$ select 'BiddingDigestBacklog'::text, public.steward_inbox(), null::uuid,
		(select count(*)::text from private.bidding_digest_recipients ('6 days')) $$,
	'and tells the steward inbox how many'
);

select public.mark_bidding_digests_checked (array(select id from private.bidding_digest_recipients ('6 days')));
select is (
	public.report_bidding_digest_backlog (),
	0,
	'once everyone is reached there is no backlog'
);

select is (
	(select count(*)::int from public.emails where event = 'BiddingDigestBacklog'),
	1,
	'and no alert'
);

-- ---- Who may -----------------------------------------------------------------------

select tests.authenticate_as(:'rev');

select throws_ok (
	'select * from public.bidding_digest_candidates ()',
	'42501',
	null,
	'a signed-in scholar cannot list candidates'
);

select throws_ok (
	format('select public.queue_bidding_digest (%L, array[''{}''], %L)', :'rev', repeat('d', 64)),
	'42501',
	null,
	'a signed-in scholar cannot queue a digest'
);

select throws_ok (
	'select * from public.bidding_digests',
	'42501',
	null,
	'a signed-in scholar cannot read when anyone was emailed'
);

select throws_ok (
	'select * from private.expertise_keys (''x'')',
	'42501',
	null,
	'nor reach the private helper'
);

select tests.clear_authentication();
set local role service_role;
select lives_ok (
	'select * from public.bidding_digest_candidates ()',
	'the service role can list candidates'
);
reset role;

select * from finish ();

rollback;
