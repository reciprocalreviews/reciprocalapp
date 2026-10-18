-- public.assignment_loads: true counts of active assignments, for the editors choosing
-- reviewers.
--
-- It is SECURITY DEFINER because the assignments SELECT policy shows an associate editor
-- only the submissions they handle, which made a busy reviewer look free. Under test:
--   * an associate editor's counts include submissions the policy hides from them
--   * pending bids, unapproved and completed assignments do not count
--   * other venues are one total per scholar, without editor seats
--   * a venue admin and an accepted associate editor get counts; an invited one, a
--     reviewer, an author and anon get nothing

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('al_minter@test.local') as minter \gset
select tests.create_scholar('al_admin@test.local') as admin \gset
select tests.create_scholar('al_ae1@test.local') as ae1 \gset
select tests.create_scholar('al_ae2@test.local') as ae2 \gset
select tests.create_scholar('al_busy@test.local') as busy \gset
select tests.create_scholar('al_author@test.local') as author \gset
select tests.create_scholar('al_ae3@test.local') as ae3 \gset
select tests.create_scholar('al_ae4@test.local') as ae4 \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset
select tests.create_role(:'ven', 0, null, false, false) as editor \gset
select tests.create_role(:'ven', 1, :'editor', false, false) as ae \gset
select tests.create_role(:'ven', 2, :'ae', false, false) as reviewer \gset
select tests.create_submission_type(:'ven') as stype \gset
-- ae3 has accepted the associate editor role but handles no paper yet; ae4 is only invited.
select tests.create_volunteer(:'ae3', :'ae', 'accepted');
select tests.create_volunteer(:'ae4', :'ae', 'invited');
select tests.create_volunteer(:'busy', :'reviewer', 'accepted');

-- Another venue, where busy reviews one paper and is the sole editor of another.
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as other \gset
select tests.create_role(:'other', 0, null, false, false) as o_editor \gset
select tests.create_role(:'other', 1, :'o_editor', false, false) as o_reviewer \gset
select tests.create_submission_type(:'other') as o_stype \gset
select tests.create_submission(:'other', :'o_stype', array[:'author']::uuid[]) as o1 \gset
select tests.create_submission(:'other', :'o_stype', array[:'author']::uuid[]) as o2 \gset
select tests.create_assignment(:'other', :'o1', :'busy', :'o_reviewer');
select tests.create_assignment(:'other', :'o2', :'busy', :'o_editor');

-- ae1 handles s1 and s2; ae2 handles s3. busy reviews all three, and has a completed
-- review on s4, a pending bid on s5 and an unapproved assignment on s6.
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s1 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s2 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s3 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s4 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s5 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s6 \gset
select tests.create_assignment(:'ven', :'s1', :'ae1', :'ae');
select tests.create_assignment(:'ven', :'s2', :'ae1', :'ae');
select tests.create_assignment(:'ven', :'s3', :'ae2', :'ae');
select tests.create_assignment(:'ven', :'s1', :'busy', :'reviewer');
select tests.create_assignment(:'ven', :'s2', :'busy', :'reviewer');
select tests.create_assignment(:'ven', :'s3', :'busy', :'reviewer');
select tests.create_assignment(:'ven', :'s4', :'busy', :'reviewer', true, false, true);
select tests.create_assignment(:'ven', :'s5', :'busy', :'reviewer', false, true);
select tests.create_assignment(:'ven', :'s6', :'busy', :'reviewer', false, false);

-- ---- An associate editor sees past the policy -----------------------------------
select tests.authenticate_as(:'ae1');
select is(
	(select count(*)::integer from public.assignments where scholar = :'busy' and venue = :'ven' and approved and not completed),
	2,
	'the SELECT policy shows ae1 only the two reviews on submissions they handle'
);
select results_eq(
	format('select role, count from public.assignment_loads(%L, array[%L]::uuid[]) where role is not null', :'ven', :'busy'),
	format('values (%L::uuid, 3)', :'reviewer'),
	'assignment_loads gives ae1 all three active reviews, not bids, unapproved or completed ones'
);
select results_eq(
	format('select count from public.assignment_loads(%L, array[%L]::uuid[]) where role is null', :'ven', :'busy'),
	$$ values (1) $$,
	'other venues count once per scholar, without editor seats'
);
select is_empty(
	format('select * from public.assignment_loads(%L, array[%L]::uuid[])', :'ven', :'author'),
	'a scholar with no active assignments has no rows'
);

-- ---- Who gets counts -------------------------------------------------------------
select tests.authenticate_as(:'admin');
select results_eq(
	format('select count from public.assignment_loads(%L, array[%L]::uuid[]) where role = %L', :'ven', :'busy', :'reviewer'),
	$$ values (3) $$,
	'a venue admin gets the true count'
);
select tests.authenticate_as(:'ae3');
select results_eq(
	format('select count from public.assignment_loads(%L, array[%L]::uuid[]) where role = %L', :'ven', :'busy', :'reviewer'),
	$$ values (3) $$,
	'an accepted associate editor with no papers yet gets the true count'
);
select tests.authenticate_as(:'ae4');
select is_empty(
	format('select * from public.assignment_loads(%L, array[%L]::uuid[])', :'ven', :'busy'),
	'an associate editor who has only been invited gets nothing'
);
select tests.authenticate_as(:'busy');
select is_empty(
	format('select * from public.assignment_loads(%L, array[%L]::uuid[])', :'ven', :'busy'),
	'a reviewer, whose role approves nothing, gets nothing'
);
select tests.authenticate_as(:'author');
select is_empty(
	format('select * from public.assignment_loads(%L, array[%L]::uuid[])', :'ven', :'busy'),
	'an author gets nothing'
);
select tests.clear_authentication();
select ok(
	not has_function_privilege('anon', 'public.assignment_loads(uuid, uuid[])', 'execute'),
	'anon cannot execute assignment_loads'
);

select * from finish();
rollback;
