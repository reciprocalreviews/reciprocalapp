-- public.completed_counts: reviews each scholar has finished at a venue, for the volunteers
-- roster's track record.
--
-- It shares can_scout_volunteers with assignment_loads. Under test:
--   * only approved, completed assignments at this venue count, in any role
--   * work at another venue does not count
--   * a venue admin and an accepted associate editor get counts; an invited one, a
--     reviewer, an author and anon get nothing

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('cc_minter@test.local') as minter \gset
select tests.create_scholar('cc_admin@test.local') as admin \gset
select tests.create_scholar('cc_ae@test.local') as ae1 \gset
select tests.create_scholar('cc_invited@test.local') as ae2 \gset
select tests.create_scholar('cc_done@test.local') as done \gset
select tests.create_scholar('cc_author@test.local') as author \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset
select tests.create_role(:'ven', 0, null, false, false) as editor \gset
select tests.create_role(:'ven', 1, :'editor', false, false) as ae \gset
select tests.create_role(:'ven', 2, :'ae', false, false) as reviewer \gset
select tests.create_submission_type(:'ven') as stype \gset
select tests.create_volunteer(:'ae1', :'ae', 'accepted');
select tests.create_volunteer(:'ae2', :'ae', 'invited');
select tests.create_volunteer(:'done', :'reviewer', 'accepted');

-- done has finished two reviews and one associate editorship here, has one review in
-- progress, and one pending bid.
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s1 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s2 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s3 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s4 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s5 \gset
select tests.create_assignment(:'ven', :'s1', :'done', :'reviewer', true, false, true);
select tests.create_assignment(:'ven', :'s2', :'done', :'reviewer', true, false, true);
select tests.create_assignment(:'ven', :'s3', :'done', :'ae', true, false, true);
select tests.create_assignment(:'ven', :'s4', :'done', :'reviewer');
select tests.create_assignment(:'ven', :'s5', :'done', :'reviewer', false, true);

-- And a finished review at another venue.
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as other \gset
select tests.create_role(:'other', 0, null, false, false) as o_editor \gset
select tests.create_role(:'other', 1, :'o_editor', false, false) as o_reviewer \gset
select tests.create_submission_type(:'other') as o_stype \gset
select tests.create_submission(:'other', :'o_stype', array[:'author']::uuid[]) as o1 \gset
select tests.create_assignment(:'other', :'o1', :'done', :'o_reviewer', true, false, true);

-- ---- Counts ----------------------------------------------------------------------
select tests.authenticate_as(:'admin');
select results_eq(
	format('select count from public.completed_counts(%L, array[%L]::uuid[])', :'ven', :'done'),
	$$ values (3) $$,
	'a venue admin gets completed work in every role here, not in-progress work, bids or other venues'
);
select is_empty(
	format('select * from public.completed_counts(%L, array[%L]::uuid[])', :'ven', :'author'),
	'a scholar with nothing completed has no row'
);

-- ---- Who gets counts -------------------------------------------------------------
select tests.authenticate_as(:'ae1');
select results_eq(
	format('select count from public.completed_counts(%L, array[%L]::uuid[])', :'ven', :'done'),
	$$ values (3) $$,
	'an accepted associate editor gets the true count'
);
select tests.authenticate_as(:'ae2');
select is_empty(
	format('select * from public.completed_counts(%L, array[%L]::uuid[])', :'ven', :'done'),
	'an associate editor who has only been invited gets nothing'
);
select tests.authenticate_as(:'done');
select is_empty(
	format('select * from public.completed_counts(%L, array[%L]::uuid[])', :'ven', :'done'),
	'a reviewer, whose role approves nothing, gets nothing'
);
select tests.authenticate_as(:'author');
select is_empty(
	format('select * from public.completed_counts(%L, array[%L]::uuid[])', :'ven', :'done'),
	'an author gets nothing'
);
select tests.clear_authentication();
select ok(
	not has_function_privilege('anon', 'public.completed_counts(uuid, uuid[])', 'execute'),
	'anon cannot execute completed_counts'
);
select ok(
	not has_function_privilege('anon', 'public.can_scout_volunteers(uuid)', 'execute'),
	'anon cannot execute can_scout_volunteers'
);

select * from finish();
rollback;
