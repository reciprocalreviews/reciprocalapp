-- What `bulk_import_submissions` reports about WHO it seated, and on how many papers.
--
-- The digest a bulk import sends is built from `seated_by`: one message per person,
-- carrying the number of submissions they now hold (SupabaseCRUD.bulkImportSubmissions).
-- That number used to count assignment ROWS, and the two seating paths are independently
-- reachable on a single row -- the file may name the venue's sole editor for some OTHER
-- role, and the sole-editor fallback then seats them a second time, because it stands
-- down only for a row that already has somebody at priority 0. One paper, two seats, and
-- a message saying two submissions had arrived. See #181.
--
-- So the assertions below are mostly about the DIFFERENCE between `seated`, which counts
-- assignments and is meant to, and `seated_by`, which counts distinct submissions per
-- person. Where the two must agree they are asserted together; the case that motivated
-- this file is the one where they must not.
--
-- The four shapes are the ones the issue asks to be covered: a person named for a
-- non-editor role, the sole editor named explicitly, the sole-editor fallback, and an
-- explicitly named editor at a venue with several of them -- where the fallback does not
-- run at all, so nothing but the file decides who is seated.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

-- ---- Fixtures (owner context) ------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('bisb_minter@test.local') as minter \gset
select tests.create_scholar('bisb_admin@test.local') as admin \gset
select tests.create_scholar('bisb_editor@test.local') as editor \gset
select tests.create_scholar('bisb_reviewer@test.local') as reviewer \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset

-- Venue A: exactly one accepted editor, so the sole-editor fallback is live. The second
-- role is what lets the file name somebody -- including the editor -- without touching
-- priority 0, which is the configuration the double-seat arises in.
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset
select tests.create_role(:'ven', 0) as editor_role \gset
select tests.create_role(:'ven', 1) as reviewer_role \gset
select tests.create_volunteer(:'editor', :'editor_role') as v_editor \gset
select tests.create_volunteer(:'reviewer', :'reviewer_role') as v_reviewer \gset
-- The editor also holds the non-editor role: seating one person in two roles is allowed
-- (they did both jobs), and a name is only seatable in a role they already hold.
select tests.create_volunteer(:'editor', :'reviewer_role') as v_editor_reviewer \gset
select tests.create_submission_type(:'ven', 10) as stype \gset

--------------------------------------------------------------------------------
-- The sole-editor fallback, on its own and across several rows
--------------------------------------------------------------------------------
select tests.authenticate_as(:'admin');
select public.bulk_import_submissions(
	:'ven',
	('[{"externalid": "FALL-1", "title": "Fallback paper", "submission_type": "' || :'stype' || '"}]')::jsonb,
	'Fallback import'
) as fallback \gset

select is(
	(:'fallback'::jsonb->'seated_by'->>:'editor')::int,
	1,
	'the sole editor is reported as holding the one submission the fallback seated them on'
);
select is(
	(:'fallback'::jsonb->>'seated')::int,
	1,
	'and that is one assignment, so the two counts agree where nothing seated twice'
);

select public.bulk_import_submissions(
	:'ven',
	('[
		{"externalid": "FALL-2", "title": "Second", "submission_type": "' || :'stype' || '"},
		{"externalid": "FALL-3", "title": "Third", "submission_type": "' || :'stype' || '"},
		{"externalid": "FALL-4", "title": "Fourth", "submission_type": "' || :'stype' || '"}
	]')::jsonb,
	'Fallback batch'
) as batch \gset

select is(
	(:'batch'::jsonb->'seated_by'->>:'editor')::int,
	3,
	'a batch of three counts three, so the digest scales with the import'
);

--------------------------------------------------------------------------------
-- A person named for a NON-editor role
--------------------------------------------------------------------------------
select public.bulk_import_submissions(
	:'ven',
	('[{"externalid": "NAMED-1", "title": "Named reviewer", "submission_type": "' || :'stype'
		|| '", "people": [{"person": "' || :'reviewer' || '", "person_role": "' || :'reviewer_role' || '"}]}]')::jsonb,
	'Named import'
) as named \gset

select is(
	(:'named'::jsonb->'seated_by'->>:'reviewer')::int,
	1,
	'somebody named for a non-editor role is reported, in whatever role the file named'
);
select is(
	(:'named'::jsonb->'seated_by'->>:'editor')::int,
	1,
	'and the fallback still seats the editor, since that row named nobody at priority 0'
);

--------------------------------------------------------------------------------
-- The regression: the sole editor, ALSO named for a non-editor role on the same row
--------------------------------------------------------------------------------
select public.bulk_import_submissions(
	:'ven',
	('[{"externalid": "BOTH-1", "title": "Two seats one paper", "submission_type": "' || :'stype'
		|| '", "people": [{"person": "' || :'editor' || '", "person_role": "' || :'reviewer_role' || '"}]}]')::jsonb,
	'Double-seat import'
) as both \gset

select is(
	(:'both'::jsonb->'seated_by'->>:'editor')::int,
	1,
	'one paper counts once, however many seats on it one person took'
);
select is(
	(:'both'::jsonb->>'seated')::int,
	2,
	'while `seated` still counts both assignments, which is what it is for'
);
select is(
	(select count(*)::int from public.assignments a
	 join public.submissions s on s.id = a.submission
	 where s.venue = :'ven' and s.externalid = 'BOTH-1' and a.scholar = :'editor'),
	2,
	'and both assignments really were written -- the count is what changed, not the seating'
);

--------------------------------------------------------------------------------
-- The sole editor named explicitly: the fallback stands down
--------------------------------------------------------------------------------
select public.bulk_import_submissions(
	:'ven',
	('[{"externalid": "SOLE-1", "title": "Named editor", "submission_type": "' || :'stype'
		|| '", "people": [{"person": "' || :'editor' || '", "person_role": "' || :'editor_role' || '"}]}]')::jsonb,
	'Sole editor named'
) as sole \gset

select is(
	(:'sole'::jsonb->'seated_by'->>:'editor')::int,
	1,
	'the sole editor named by the file holds the one submission'
);
select is(
	(:'sole'::jsonb->>'seated')::int,
	1,
	'and is seated once, because the fallback stands down for a row already at priority 0'
);
select tests.clear_authentication();

--------------------------------------------------------------------------------
-- Venue B: SEVERAL editors, so the fallback never runs and only the file seats anyone
--------------------------------------------------------------------------------
select tests.create_scholar('bisb_admin_b@test.local') as admin_b \gset
select tests.create_scholar('bisb_editor_b1@test.local') as editor_b1 \gset
select tests.create_scholar('bisb_editor_b2@test.local') as editor_b2 \gset

select tests.create_venue(:'cur', array[:'admin_b']::uuid[]) as ven_b \gset
select tests.create_role(:'ven_b', 0) as editor_role_b \gset
select tests.create_volunteer(:'editor_b1', :'editor_role_b') as vb1 \gset
select tests.create_volunteer(:'editor_b2', :'editor_role_b') as vb2 \gset
select tests.create_submission_type(:'ven_b', 10) as stype_b \gset

select tests.authenticate_as(:'admin_b');
select public.bulk_import_submissions(
	:'ven_b',
	('[{"externalid": "MULTI-1", "title": "Named among several", "submission_type": "' || :'stype_b'
		|| '", "people": [{"person": "' || :'editor_b1' || '", "person_role": "' || :'editor_role_b' || '"}]}]')::jsonb,
	'Multi-editor import'
) as multi \gset

select is(
	(:'multi'::jsonb->'seated_by'->>:'editor_b1')::int,
	1,
	'an editor the file names at a venue with several is seated, and counted once'
);
-- The reason the old prose was wrong for this recipient: nothing about being the only
-- editor was true of them, and nothing automatic seated them.
select is(
	(select count(*)::int from jsonb_object_keys(:'multi'::jsonb->'seated_by')),
	1,
	'and nobody else is seated, because several editors means no automatic seat'
);

select public.bulk_import_submissions(
	:'ven_b',
	('[{"externalid": "MULTI-2", "title": "Named by nobody", "submission_type": "' || :'stype_b' || '"}]')::jsonb,
	'Unnamed import'
) as unnamed \gset

select is(
	:'unnamed'::jsonb->'seated_by',
	'{}'::jsonb,
	'a row naming nobody at a venue with several editors seats nobody at all'
);
select is(
	(:'unnamed'::jsonb->>'waiting')::int,
	1,
	'and is reported as waiting for an editor instead'
);
select tests.clear_authentication();

select * from finish();
rollback;
