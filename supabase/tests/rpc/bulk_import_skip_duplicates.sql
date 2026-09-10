-- Tests that a bulk import SKIPS a manuscript the venue already has rather than refusing
-- the batch. Defined in migration 20260910000000_bulk_import_skip_duplicates.sql.
--
-- The rule this pins is the difference between "some of this file is already here" and
-- "this file is wrong". The first is the ordinary input: a venue exports its queue,
-- imports it, and exports it again a month later still carrying the same manuscripts. It
-- used to raise 23505 on submissions_venue_externalid_unique and roll back every
-- submission, assignment and mint the import had already written -- so one overlapping
-- row cost the whole afternoon.
--
-- What must NOT change is everything else about that rollback. An ineligible name, a
-- role from another venue, two priority-0 seats on one row: those still take the batch
-- down, because they mean the form was bypassed rather than that the file overlaps. The
-- last section is what keeps `on conflict do nothing` from having quietly turned every
-- failure into a silently missing submission.
--
-- The money assertions are the point of the middle section. A skipped row must not fund
-- anything: the mint is sized from the rows actually written, so a batch whose overlap
-- was counted would propose tokens for manuscripts that already exist and were already
-- paid for once.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(23);

-- ---- Fixtures (owner context) ------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('bisd_minter@test.local') as minter \gset
select tests.create_scholar('bisd_admin@test.local') as admin \gset
select tests.create_scholar('bisd_editor@test.local') as editor \gset
select tests.create_scholar('bisd_author@test.local') as author \gset
select tests.create_scholar('bisd_outsider@test.local') as outsider \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset

-- Exactly one accepted editor, so the sole-editor fallback seats somebody on every row
-- that is written -- which is how a skipped row proves it wrote nothing: no submission,
-- and no assignment either.
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset
select tests.create_role(:'ven', 0) as editor_role \gset
select tests.create_volunteer(:'editor', :'editor_role') as v1 \gset
select tests.create_submission_type(:'ven', 10) as stype \gset

-- The manuscript the venue already has -- an ordinary authored submission, not a
-- previously imported one. That is the stronger fixture: it carries a title, an author
-- and a payment of its own, so anything the import quietly merged into it would show.
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as existing \gset
update public.submissions
set externalid = 'ALREADY-1', title = 'The original title'
where id = :'existing';

--------------------------------------------------------------------------------
-- A batch that overlaps: the overlap is skipped, the rest is written
--------------------------------------------------------------------------------
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$, $$
		|| quote_literal('[
			{"externalid": "ALREADY-1", "title": "A resubmitted title", "submission_type": "' || :'stype' || '"},
			{"externalid": "NEW-1", "title": "First new paper", "submission_type": "' || :'stype' || '"},
			{"externalid": "NEW-2", "title": "Second new paper", "submission_type": "' || :'stype' || '"}
		]') || $$::jsonb, 'Backlog import' ) $$,
	'a batch containing a manuscript the venue already has does not raise'
);

select public.bulk_import_submissions(
	:'ven',
	('[
		{"externalid": "ALREADY-1", "title": "A resubmitted title", "submission_type": "' || :'stype' || '"},
		{"externalid": "NEW-3", "title": "Third new paper", "submission_type": "' || :'stype' || '"}
	]')::jsonb,
	'Second backlog import'
) as result \gset
select tests.clear_authentication();

select is(
	(:'result'::jsonb->>'skipped')::int,
	1,
	'the manuscript already at the venue is counted as skipped'
);
select is(
	jsonb_array_length(:'result'::jsonb->'submission_ids'),
	1,
	'only the new manuscript is reported as written'
);
select is(
	(:'result'::jsonb->>'mint_amount')::int,
	10,
	'the mint is sized to the rows written, not to the rows submitted'
);
select is(
	(:'result'::jsonb->>'waiting')::int,
	0,
	'a skipped row is not counted as waiting for an editor'
);

-- The rows that were not skipped landed, from both calls above.
select is(
	(select count(*)::int from public.submissions where venue = :'ven' and externalid in ('NEW-1', 'NEW-2', 'NEW-3')),
	3,
	'every manuscript the venue did not already have was imported'
);
select is(
	(select count(*)::int from public.submissions where venue = :'ven' and externalid = 'ALREADY-1'),
	1,
	'the manuscript the venue already had was not duplicated'
);

-- Skipped means untouched, not merged: `on conflict do nothing` must not become an
-- upsert, or a re-imported export would silently rewrite the venue's own edits.
select is(
	(select title from public.submissions where venue = :'ven' and externalid = 'ALREADY-1'),
	'The original title',
	'the existing manuscript keeps its own title rather than the file''s'
);
select is(
	(select imported from public.submissions where venue = :'ven' and externalid = 'ALREADY-1'),
	false,
	'the existing manuscript is not re-flagged as imported'
);
select is(
	(select authors from public.submissions where venue = :'ven' and externalid = 'ALREADY-1'),
	array[:'author']::uuid[],
	'the existing manuscript keeps its authors, which an imported row would not have'
);

-- A skipped row writes no assignment. The sole-editor fallback seats somebody on every
-- row that IS written, so this is what separates "skipped" from "written quietly".
select is(
	(select count(*)::int from public.assignments a
	 join public.submissions s on s.id = a.submission
	 where s.venue = :'ven' and s.externalid = 'ALREADY-1'),
	0,
	'no assignment is written for a skipped row'
);
select is(
	(select count(*)::int from public.assignments a
	 join public.submissions s on s.id = a.submission
	 where s.venue = :'ven' and s.externalid in ('NEW-1', 'NEW-2', 'NEW-3') and a.scholar = :'editor'),
	3,
	'the venue''s sole editor is still seated on every row that was written'
);

-- Two mints, one per call, each sized to what its call actually wrote: 20 then 10.
select is(
	(select count(*)::int from public.transactions
	 where to_venue = :'ven' and status = 'proposed' and cardinality(tokens) = 20),
	1,
	'the first import proposes a mint for its two written rows only'
);
select is(
	(select count(*)::int from public.transactions
	 where to_venue = :'ven' and status = 'proposed' and cardinality(tokens) = 10),
	1,
	'the second import proposes a mint for its one written row only'
);

--------------------------------------------------------------------------------
-- A batch that is entirely already here
--------------------------------------------------------------------------------
-- The form refuses to send this, so arriving here means its list of existing IDs had
-- gone stale -- the page left open while somebody else imported the same file. It must
-- be a no-op rather than an error: there is nothing left to write and nothing to fund.
select tests.authenticate_as(:'admin');
select public.bulk_import_submissions(
	:'ven',
	('[
		{"externalid": "NEW-1", "title": "First new paper", "submission_type": "' || :'stype' || '"},
		{"externalid": "NEW-2", "title": "Second new paper", "submission_type": "' || :'stype' || '"}
	]')::jsonb,
	'A file sent twice'
) as allskipped \gset
select tests.clear_authentication();

select is(
	(:'allskipped'::jsonb->>'skipped')::int,
	2,
	'every row of a file that is entirely already here is skipped'
);
select is(
	jsonb_array_length(:'allskipped'::jsonb->'submission_ids'),
	0,
	'nothing is written'
);
select is(
	(:'allskipped'::jsonb->>'mint_amount')::int,
	0,
	'nothing is minted'
);
select is(
	:'allskipped'::jsonb->>'transaction_id',
	null,
	'no mint transaction is proposed at all when nothing was written'
);
select is(
	(select count(*)::int from public.submissions where venue = :'ven'),
	4,
	'the venue still holds only the manuscripts it had'
);

--------------------------------------------------------------------------------
-- Everything else still rolls the whole batch back
--------------------------------------------------------------------------------
-- The skip is for an overlapping file, which is expected input. A name that is not an
-- eligible volunteer means the form was bypassed, and a half-seated batch is harder to
-- reason about than none -- so this must still take down the rows around it rather than
-- quietly importing them unseated.
select tests.authenticate_as(:'admin');
select throws_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$, $$
		|| quote_literal('[
			{"externalid": "ROLLBACK-1", "title": "Fine on its own", "submission_type": "' || :'stype' || '"},
			{"externalid": "ROLLBACK-2", "title": "Names an outsider", "submission_type": "' || :'stype' || '",
			 "people": [{"person": "' || :'outsider' || '", "person_role": "' || :'editor_role' || '"}]}
		]') || $$::jsonb, 'Bypassed the form' ) $$,
	'A named person must already be an accepted, active volunteer in that role',
	'an ineligible name still refuses the import'
);
select tests.clear_authentication();

select is(
	(select count(*)::int from public.submissions where venue = :'ven' and externalid like 'ROLLBACK-%'),
	0,
	'the row that was fine on its own is rolled back with the rest of the batch'
);

-- And the venue is exactly where it was before that attempt.
select is(
	(select count(*)::int from public.submissions where venue = :'ven'),
	4,
	'a refused batch leaves the venue untouched'
);

-- A non-admin still cannot import, skip clause or not.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$, $$
		|| quote_literal('[{"externalid": "NOPE-1", "title": "Not yours", "submission_type": "' || :'stype' || '"}]')
		|| $$::jsonb, 'Not an admin' ) $$,
	'Only venue admins can bulk import submissions',
	'a non-admin is still refused'
);
select tests.clear_authentication();

select * from finish();
rollback;
