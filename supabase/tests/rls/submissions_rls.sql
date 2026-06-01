-- RLS tests for public.submissions.
--
-- Authorization model under test:
--   SELECT  authors, accepted volunteers on a biddable role at the venue, and
--           scholars with an approved assignment to the submission.
--   INSERT  anyone authenticated may create a submission.
--   UPDATE  authors, or scholars with an approved priority-0 role assignment.
--   DELETE  venue admins only.
--   IMMUTABILITY  status/completed_at are revoked from authenticated at the
--           column level: even a permitted updater (an author) gets 42501.
--   AUTHOR-LIST LOCK  the enforce_submission_author_edits trigger forbids any
--           non-priority-0 actor (e.g. an author) from changing
--           authors/payments/transactions; a priority-0 assigned scholar may.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('sub_author@test.local')   as author    \gset
select tests.create_scholar('sub_bidder@test.local')   as bidder    \gset
select tests.create_scholar('sub_assigned@test.local') as assigned  \gset
select tests.create_scholar('sub_prio0@test.local')    as prio0     \gset
select tests.create_scholar('sub_admin@test.local')    as admin     \gset
select tests.create_scholar('sub_minter@test.local')   as minter    \gset
select tests.create_scholar('sub_outsider@test.local') as outsider  \gset

-- Currency minter and venue admin must be DISTINCT scholars (the no_minter_admins
-- / no_admin_minters triggers forbid overlap).
select tests.create_currency(array[:'minter']::uuid[])                  as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[])              as ven \gset
select tests.create_submission_type(:'ven')                            as styp \gset

-- A biddable role at the venue + an accepted volunteer on it.
select tests.create_role(:'ven', 1, null, true, false)                  as biddable_role \gset
select tests.create_volunteer(:'bidder', :'biddable_role', 'accepted')  as biddable_vol  \gset

-- A non-priority-0 role used for the plain "assigned scholar" SELECT case.
select tests.create_role(:'ven', 2, null, false, false)                 as review_role \gset
-- A priority-0 role used for the editor (priority-0) UPDATE / author-lock cases.
select tests.create_role(:'ven', 0, null, false, false)                 as editor_role \gset

-- The main submission, authored by :author.
select tests.create_submission(:'ven', :'styp', array[:'author']::uuid[]) as sub_main \gset
-- A second submission used solely for the DELETE cases.
select tests.create_submission(:'ven', :'styp', array[:'author']::uuid[]) as sub_del  \gset

-- :assigned has an approved (non-priority-0) assignment to sub_main → may SELECT.
select tests.create_assignment(:'ven', :'sub_main', :'assigned', :'review_role', true, false) as asn_review \gset
-- :prio0 has an approved priority-0 assignment to sub_main → may UPDATE + edit authors.
select tests.create_assignment(:'ven', :'sub_main', :'prio0', :'editor_role', true, false)    as asn_editor \gset

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'submissions',
	array[
		'admins, authors, assigned, and bidders can view submissions',
		'anyone can create submissions, admins for imports',
		'authors and editors can update submissions',
		'admins can delete submissions'
	]
);

-- ---- SELECT -------------------------------------------------------------------
select tests.authenticate_as(:'author');
select isnt_empty(
	$$ select 1 from public.submissions where id = $$ || quote_literal(:'sub_main'),
	'an author can see their own submission'
);

select tests.authenticate_as(:'bidder');
select isnt_empty(
	$$ select 1 from public.submissions where id = $$ || quote_literal(:'sub_main'),
	'an accepted volunteer on a biddable role at the venue can see the submission'
);

select tests.authenticate_as(:'assigned');
select isnt_empty(
	$$ select 1 from public.submissions where id = $$ || quote_literal(:'sub_main'),
	'a scholar with an approved assignment can see the submission'
);

select tests.authenticate_as(:'outsider');
select is_empty(
	$$ select 1 from public.submissions where id = $$ || quote_literal(:'sub_main'),
	'an unrelated scholar cannot see the submission'
);

select tests.authenticate_as_anon();
select is_empty(
	$$ select 1 from public.submissions where id = $$ || quote_literal(:'sub_main'),
	'anonymous visitors cannot see submissions'
);

-- ---- UPDATE (policy branches) -------------------------------------------------
-- An author may update an editable column (title).
select tests.authenticate_as(:'author');
select lives_ok(
	$$ update public.submissions set title = 'by-author' where id = $$ || quote_literal(:'sub_main'),
	'an author can update an editable column on their submission'
);
select tests.clear_authentication();
select is(
	(select title from public.submissions where id = :'sub_main'),
	'by-author',
	'the author edit took effect'
);

-- A priority-0 assigned scholar (editor) may also update.
select tests.authenticate_as(:'prio0');
select lives_ok(
	$$ update public.submissions set title = 'by-editor' where id = $$ || quote_literal(:'sub_main'),
	'a priority-0 assigned scholar (editor) can update the submission'
);

-- An unrelated scholar's UPDATE is filtered by the using clause (0 rows, no error).
select tests.authenticate_as(:'outsider');
update public.submissions set title = 'by-outsider' where id = :'sub_main';
select tests.clear_authentication();
select is(
	(select title from public.submissions where id = :'sub_main'),
	'by-editor',
	'an unrelated scholar cannot update the submission (no-op)'
);

-- ---- UPDATE (immutability of status/completed_at) -----------------------------
-- status is revoked from authenticated at the column level: even an author,
-- who passes the row policy, cannot write it.
select tests.authenticate_as(:'author');
select throws_ok(
	$$ update public.submissions set status = 'done' where id = $$ || quote_literal(:'sub_main'),
	'42501',
	null,
	'status is immutable: even an author cannot set it directly'
);

-- ---- UPDATE (author-list lock trigger) ----------------------------------------
-- An author passes RLS but the enforce_submission_author_edits trigger forbids
-- them from changing the author list (they are not priority-0 assigned).
select tests.authenticate_as(:'author');
select throws_ok(
	$$ update public.submissions
	   set authors = array[ $$ || quote_literal(:'author') || $$, $$ || quote_literal(:'outsider') || $$ ]::uuid[],
	       payments = array[0, 0],
	       transactions = array['00000000-0000-0000-0000-000000000000'::uuid, '00000000-0000-0000-0000-000000000000'::uuid]
	   where id = $$ || quote_literal(:'sub_main'),
	null,
	null,
	'an author cannot change the author list (trigger raises)'
);

-- A priority-0 assigned scholar may change the author list.
select tests.authenticate_as(:'prio0');
select lives_ok(
	$$ update public.submissions
	   set authors = array[ $$ || quote_literal(:'author') || $$, $$ || quote_literal(:'outsider') || $$ ]::uuid[],
	       payments = array[0, 0],
	       transactions = array['00000000-0000-0000-0000-000000000000'::uuid, '00000000-0000-0000-0000-000000000000'::uuid]
	   where id = $$ || quote_literal(:'sub_main'),
	'a priority-0 assigned scholar can change the author list'
);
select tests.clear_authentication();
select is(
	(select cardinality(authors) from public.submissions where id = :'sub_main'),
	2,
	'the priority-0 author-list edit took effect'
);

-- ---- INSERT -------------------------------------------------------------------
-- Any authenticated scholar may create a submission.
select tests.authenticate_as(:'outsider');
select lives_ok(
	$$ insert into public.submissions (venue, externalid, submission_type, authors, payments, transactions)
	   values ( $$ || quote_literal(:'ven') || $$, 'new-ext', $$ || quote_literal(:'styp') || $$,
	            array[ $$ || quote_literal(:'outsider') || $$ ]::uuid[],
	            array[0], array['00000000-0000-0000-0000-000000000000'::uuid]) $$,
	'any authenticated scholar can create a submission'
);

-- Anonymous visitors are not granted the INSERT policy (it is to authenticated).
select tests.authenticate_as_anon();
select throws_ok(
	$$ insert into public.submissions (venue, externalid, submission_type, authors, payments, transactions)
	   values ( $$ || quote_literal(:'ven') || $$, 'anon-ext', $$ || quote_literal(:'styp') || $$,
	            array[ $$ || quote_literal(:'outsider') || $$ ]::uuid[],
	            array[0], array['00000000-0000-0000-0000-000000000000'::uuid]) $$,
	'42501',
	null,
	'an anonymous visitor cannot create a submission'
);

-- ---- DELETE -------------------------------------------------------------------
-- A non-admin's DELETE is filtered by the using clause (0 rows, no error).
select tests.authenticate_as(:'outsider');
delete from public.submissions where id = :'sub_del';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.submissions where id = :'sub_del'),
	1,
	'a non-admin cannot delete a submission'
);

-- A venue admin can delete a submission at their venue.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ delete from public.submissions where id = $$ || quote_literal(:'sub_del'),
	'a venue admin can delete a submission'
);

select * from finish();
rollback;
