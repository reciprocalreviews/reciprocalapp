-- RLS + RPC tests for public.thanks (author thank-you notes to reviewers, #22).
--
-- Authorization model under test:
--   SELECT   author (own, any status); venue admins / priority-0 editors (all);
--            approved notes visible to the submission's approved assignees.
--   propose_thanks  only an author of a DONE submission; held 'proposed' when the
--                   venue vets, else 'approved'.
--   approve/decline_thanks  venue admin or priority-0 editor only.
--   queue_thanks_emails  fans rendered copy out to a server-resolved audience;
--                   'recipients' requires an approved note and a vetter (or the
--                   author when the venue has vetting off), so an author cannot
--                   bypass vetting to message reviewers directly.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('th_minter@test.local') as minter \gset
select tests.create_scholar('th_admin@test.local') as admin \gset
select tests.create_scholar('th_author@test.local') as author \gset
select tests.create_scholar('th_reviewer@test.local') as reviewer \gset
select tests.create_scholar('th_other@test.local') as other \gset

select tests.create_currency(array[:'minter']::uuid[]) as currency \gset
select tests.create_venue(:'currency', array[:'admin']::uuid[]) as venue \gset
select tests.create_role(:'venue', 1) as role \gset
select tests.create_submission_type(:'venue') as stype \gset
select tests.create_submission(:'venue', :'stype', array[:'author']::uuid[]) as sub \gset
select tests.create_submission(:'venue', :'stype', array[:'author']::uuid[]) as sub2 \gset

-- The reviewer is an approved assignee of both submissions.
select tests.create_assignment(:'venue', :'sub', :'reviewer', :'role') as a1 \gset
select tests.create_assignment(:'venue', :'sub2', :'reviewer', :'role') as a2 \gset

-- Thanks are only allowed once a submission is done.
update public.submissions set status = 'done' where id in (:'sub', :'sub2');

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'thanks',
	array[
		'authors, vetters, and recipients can see thanks',
		'authors can propose thanks on done submissions',
		'authors can edit pending thanks',
		'authors can withdraw pending thanks'
	]
);

-- ---- propose_thanks ------------------------------------------------------------
-- A non-author cannot thank.
select tests.authenticate_as(:'reviewer');
select throws_ok(
	$$ select public.propose_thanks( $$ || quote_literal(:'sub') || $$, 'sneaky') $$,
	'P0001', null,
	'a non-author cannot propose thanks'
);

-- An author of a non-done submission cannot thank.
select tests.clear_authentication();
update public.submissions set status = 'reviewing' where id = :'sub';
select tests.authenticate_as(:'author');
select throws_ok(
	$$ select public.propose_thanks( $$ || quote_literal(:'sub') || $$, 'too early') $$,
	'P0001', null,
	'an author cannot thank before the submission is done'
);
select tests.clear_authentication();
update public.submissions set status = 'done' where id = :'sub';

-- An author of a done submission can thank.
select tests.authenticate_as(:'author');
select lives_ok(
	$$ select public.propose_thanks( $$ || quote_literal(:'sub') || $$, 'Thank you all!') $$,
	'an author of a done submission can propose thanks'
);

-- With vetting on (the default), the note is held 'proposed'.
select tests.clear_authentication();
select is(
	(select status::text from public.thanks where submission = :'sub' and author = :'author'),
	'proposed',
	'a note is held proposed when the venue vets thanks'
);
select id as note from public.thanks where submission = :'sub' and author = :'author' \gset

-- ---- SELECT visibility --------------------------------------------------------
select tests.authenticate_as(:'author');
select isnt_empty(
	$$ select 1 from public.thanks where id = $$ || quote_literal(:'note'),
	'the author can see their own proposed note'
);

select tests.authenticate_as(:'reviewer');
select is_empty(
	$$ select 1 from public.thanks where id = $$ || quote_literal(:'note'),
	'a reviewer cannot see a note while it is proposed'
);

select tests.authenticate_as(:'other');
select is_empty(
	$$ select 1 from public.thanks where id = $$ || quote_literal(:'note'),
	'an unrelated scholar cannot see the note'
);

-- ---- queue_thanks_emails: notify vetters (author) -----------------------------
select tests.authenticate_as(:'author');
select lives_ok(
	$$ select public.queue_thanks_emails( $$ || quote_literal(:'note') || $$, 'vetters', 's', 'm') $$,
	'the author can notify the venue vetters'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.emails where event = 'ThanksPendingReview' and scholar = :'admin'),
	1,
	'the venue admin is emailed to review the pending note'
);

-- The author cannot bypass vetting to deliver to reviewers (note not approved).
select tests.authenticate_as(:'author');
select throws_ok(
	$$ select public.queue_thanks_emails( $$ || quote_literal(:'note') || $$, 'recipients', 's', 'm') $$,
	'P0001', null,
	'an author cannot deliver an unapproved note to reviewers'
);

-- ---- approve_thanks -----------------------------------------------------------
-- A non-vetter cannot approve.
select tests.authenticate_as(:'reviewer');
select throws_ok(
	$$ select public.approve_thanks( $$ || quote_literal(:'note') || $$ ) $$,
	'P0001', null,
	'a non-vetter cannot approve a note'
);

-- The admin can approve.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ select public.approve_thanks( $$ || quote_literal(:'note') || $$ ) $$,
	'a venue admin can approve a note'
);

select tests.clear_authentication();
select is(
	(select status::text from public.thanks where id = :'note'),
	'approved',
	'the note is approved after the admin approves it'
);

-- A vetter can deliver the approved note to the (server-resolved) reviewers.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ select public.queue_thanks_emails( $$ || quote_literal(:'note') || $$, 'recipients', 's', 'm') $$,
	'a venue admin can deliver an approved note to reviewers'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.emails where event = 'ThanksReceived' and scholar = :'reviewer'),
	1,
	'the reviewer is emailed the approved note'
);

-- The recipient reviewer can now see the approved note.
select tests.authenticate_as(:'reviewer');
select isnt_empty(
	$$ select 1 from public.thanks where id = $$ || quote_literal(:'note'),
	'the reviewer can see the note once approved'
);

-- ---- decline_thanks -----------------------------------------------------------
select tests.authenticate_as(:'author');
select lives_ok(
	$$ select public.propose_thanks( $$ || quote_literal(:'sub2') || $$, 'Thanks for sub2') $$,
	'the author can propose thanks on the second submission'
);
select tests.clear_authentication();
select id as note2 from public.thanks where submission = :'sub2' and author = :'author' \gset

select tests.authenticate_as(:'admin');
select lives_ok(
	$$ select public.decline_thanks( $$ || quote_literal(:'note2') || $$, 'Please keep it about the work.') $$,
	'a venue admin can decline a note with a reason'
);
select lives_ok(
	$$ select public.queue_thanks_emails( $$ || quote_literal(:'note2') || $$, 'author', 's', 'm') $$,
	'a venue admin can notify the author of the decline'
);

select tests.clear_authentication();
select is(
	(select status::text || '|' || coalesce(decline_reason, '') from public.thanks where id = :'note2'),
	'declined|Please keep it about the work.',
	'the note is declined and records the reason'
);
select is(
	(select count(*)::int from public.emails where event = 'ThanksDeclined' and scholar = :'author'),
	1,
	'the author is emailed that their note was declined'
);

select * from finish();
rollback;
