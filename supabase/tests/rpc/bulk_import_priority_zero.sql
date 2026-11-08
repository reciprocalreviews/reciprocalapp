-- Tests who may bulk import: a venue's admins and its priority-0 editors, and nobody
-- else. Defined in migration 20261011000000_bulk_import_priority_zero.sql.
--
-- The editor test is public.isPriorityZero: an `accepted` volunteer in a priority-0
-- role, active or not. A paused editor is still the venue's editor, so they may import;
-- an editor who has only been invited is not one yet, and a volunteer in any other role
-- is not one at all. The INSERT policy on imported rows states the same rule, and is
-- tested directly because authenticated holds INSERT on the table.
--
-- Letting editors in must not let them spend: the import's mint is still only proposed.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

-- ---- Fixtures (owner context) ------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('bipz_minter@test.local') as minter \gset
select tests.create_scholar('bipz_admin@test.local') as admin \gset
select tests.create_scholar('bipz_editor@test.local') as editor \gset
select tests.create_scholar('bipz_paused@test.local') as paused \gset
select tests.create_scholar('bipz_invited@test.local') as invited \gset
select tests.create_scholar('bipz_reviewer@test.local') as reviewer \gset
select tests.create_scholar('bipz_outsider@test.local') as outsider \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset
select tests.create_role(:'ven', 0) as editor_role \gset
select tests.create_role(:'ven', 1) as reviewer_role \gset
select tests.create_volunteer(:'editor', :'editor_role') as v_editor \gset
select tests.create_volunteer(:'paused', :'editor_role') as v_paused \gset
select tests.create_volunteer(:'invited', :'editor_role', 'invited') as v_invited \gset
select tests.create_volunteer(:'reviewer', :'reviewer_role') as v_reviewer \gset
update public.volunteers set active = false where id = :'v_paused';
select tests.create_submission_type(:'ven', 10) as stype \gset

--------------------------------------------------------------------------------
-- An editor who is not an admin may import
--------------------------------------------------------------------------------
select tests.authenticate_as(:'editor');
select lives_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$, $$
		|| quote_literal('[{"externalid": "ED-1", "title": "From the editor", "submission_type": "' || :'stype' || '"}]')
		|| $$::jsonb, 'Editor import' ) $$,
	'a priority-0 editor who is not an admin can bulk import'
);
select tests.clear_authentication();

select is(
	(select count(*)::int from public.submissions where venue = :'ven' and externalid = 'ED-1' and imported),
	1,
	'the editor''s import wrote the submission'
);

-- The mint is attributed to the editor and still waits on a minter.
select results_eq(
	$$ select creator, status::text, cardinality(tokens) from public.transactions
	   where to_venue = $$ || quote_literal(:'ven') || $$ and purpose = 'Editor import' $$,
	$$ values ($$ || quote_literal(:'editor') || $$::uuid, 'proposed', 10) $$,
	'an editor''s import only proposes its mint'
);

-- A paused editor is still the venue's editor.
select tests.authenticate_as(:'paused');
select lives_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$, $$
		|| quote_literal('[{"externalid": "ED-2", "title": "From a paused editor", "submission_type": "' || :'stype' || '"}]')
		|| $$::jsonb, '' ) $$,
	'an editor who has paused volunteering can still bulk import'
);
select tests.clear_authentication();

--------------------------------------------------------------------------------
-- Nobody else may
--------------------------------------------------------------------------------
select tests.authenticate_as(:'invited');
select throws_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$, $$
		|| quote_literal('[{"externalid": "NO-1", "title": "Not yet", "submission_type": "' || :'stype' || '"}]')
		|| $$::jsonb, '' ) $$,
	'Only venue admins and editors can bulk import submissions',
	'an editor who has only been invited cannot import'
);
select tests.clear_authentication();

select tests.authenticate_as(:'reviewer');
select throws_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$, $$
		|| quote_literal('[{"externalid": "NO-2", "title": "Wrong role", "submission_type": "' || :'stype' || '"}]')
		|| $$::jsonb, '' ) $$,
	'Only venue admins and editors can bulk import submissions',
	'a volunteer in a lower-priority role cannot import'
);
select tests.clear_authentication();

select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$, $$
		|| quote_literal('[{"externalid": "NO-3", "title": "Not yours", "submission_type": "' || :'stype' || '"}]')
		|| $$::jsonb, '' ) $$,
	'Only venue admins and editors can bulk import submissions',
	'an outsider cannot import'
);
select tests.clear_authentication();

select is(
	(select count(*)::int from public.submissions where venue = :'ven' and externalid like 'NO-%'),
	0,
	'a refused import writes nothing'
);

--------------------------------------------------------------------------------
-- The INSERT policy on imported rows says the same
--------------------------------------------------------------------------------
select tests.authenticate_as(:'editor');
select lives_ok(
	$$ insert into public.submissions (venue, externalid, submission_type, authors, payments, transactions, imported)
	   values ($$ || quote_literal(:'ven') || $$, 'DIRECT-1', $$ || quote_literal(:'stype')
		|| $$, '{}', '{}', '{}', true) $$,
	'an editor may insert an imported row'
);
select tests.clear_authentication();

select tests.authenticate_as(:'reviewer');
select throws_ok(
	$$ insert into public.submissions (venue, externalid, submission_type, authors, payments, transactions, imported)
	   values ($$ || quote_literal(:'ven') || $$, 'DIRECT-2', $$ || quote_literal(:'stype')
		|| $$, '{}', '{}', '{}', true) $$,
	'42501',
	null,
	'a volunteer in a lower-priority role may not insert an imported row'
);
select tests.clear_authentication();

select tests.authenticate_as(:'admin');
select lives_ok(
	$$ insert into public.submissions (venue, externalid, submission_type, authors, payments, transactions, imported)
	   values ($$ || quote_literal(:'ven') || $$, 'DIRECT-3', $$ || quote_literal(:'stype')
		|| $$, '{}', '{}', '{}', true) $$,
	'an admin may still insert an imported row'
);
select tests.clear_authentication();

select * from finish();
rollback;
