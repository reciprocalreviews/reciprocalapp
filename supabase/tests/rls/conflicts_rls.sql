-- RLS tests for public.conflicts.
--
-- Authorization model under test:
--   SELECT  any authenticated scholar (using true); anon cannot.
--   INSERT  admins of the submission's venue, OR a volunteer for the submission's
--           venue declaring a conflict for *themselves* (the volunteer's scholarid
--           must equal the conflict's scholarid, and the volunteer's role must
--           belong to the submission's venue).
--   UPDATE  admins of the submission's venue only.
--   DELETE  admins of the submission's venue only.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
-- vadmin administers the venue; minter mints the currency (must be disjoint).
select tests.create_scholar('conf_vadmin@test.local') as vadmin \gset
select tests.create_scholar('conf_minter@test.local') as minter \gset
select tests.create_scholar('conf_volunteer@test.local') as volunteer \gset
select tests.create_scholar('conf_author@test.local') as author \gset
select tests.create_scholar('conf_outsider@test.local') as outsider \gset
-- A second venue's admin, to prove cross-venue admins are denied.
select tests.create_scholar('conf_other_admin@test.local') as other_admin \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'vadmin']::uuid[]) as ven \gset
select tests.create_submission_type(:'ven') as stype \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as sub \gset

-- A separate venue (different admin, same currency is fine since minter disjoint).
select tests.create_venue(:'cur', array[:'other_admin']::uuid[]) as other_ven \gset

-- A BIDDABLE role at the venue and an accepted volunteer for it. The role must be
-- biddable so the volunteer can see the submission: the INSERT policy's with-check
-- reads submissions to resolve the venue, and that read is itself subject to the
-- submissions SELECT policy (only authors/assignees/biddable-role volunteers).
select tests.create_role(:'ven', 0, null, true) as role \gset
select tests.create_volunteer(:'volunteer', :'role') as vol \gset

-- A pre-existing conflict (admin-created) for the update/delete probes.
insert into public.conflicts (submissionid, scholarid, reason)
values (:'sub', :'author', 'pre-existing');

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'conflicts',
	array[
		'anyone can see conflicts',
		'admins and volunteers can create conflicts',
		'admins can update conflicts',
		'admins can delete conflicts'
	]
);

-- ---- SELECT -------------------------------------------------------------------
-- Any authenticated scholar can see conflicts (using true), even an outsider.
select tests.authenticate_as(:'outsider');
select isnt_empty(
	$$ select 1 from public.conflicts where submissionid = $$ || quote_literal(:'sub'),
	'any authenticated scholar can see conflicts'
);

-- Anonymous visitors cannot (policy is authenticated-only).
select tests.authenticate_as_anon();
select is_empty(
	$$ select 1 from public.conflicts where submissionid = $$ || quote_literal(:'sub'),
	'anonymous visitors cannot see conflicts'
);

-- ---- INSERT -------------------------------------------------------------------
-- A venue admin can create a conflict for any scholar in their venue.
select tests.authenticate_as(:'vadmin');
select lives_ok(
	$$ insert into public.conflicts (submissionid, scholarid, reason)
	   values ( $$ || quote_literal(:'sub') || $$, $$ || quote_literal(:'outsider') || $$, 'admin made' ) $$,
	'a venue admin can create a conflict for the submission'
);

-- A volunteer for the venue can create a conflict for themselves.
select tests.authenticate_as(:'volunteer');
select lives_ok(
	$$ insert into public.conflicts (submissionid, scholarid, reason)
	   values ( $$ || quote_literal(:'sub') || $$, $$ || quote_literal(:'volunteer') || $$, 'I have a conflict' ) $$,
	'a volunteer for the venue can declare a conflict for themselves'
);

-- A volunteer cannot create a conflict for a *different* scholar (the volunteer
-- branch requires volunteers.scholarid = conflicts.scholarid).
select tests.authenticate_as(:'volunteer');
select throws_ok(
	$$ insert into public.conflicts (submissionid, scholarid, reason)
	   values ( $$ || quote_literal(:'sub') || $$, $$ || quote_literal(:'author') || $$, 'not mine' ) $$,
	'42501',
	null,
	'a volunteer cannot declare a conflict for another scholar'
);

-- An outsider (neither admin nor volunteer for the venue) cannot create a conflict.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ insert into public.conflicts (submissionid, scholarid, reason)
	   values ( $$ || quote_literal(:'sub') || $$, $$ || quote_literal(:'outsider') || $$, 'sneaky' ) $$,
	'42501',
	null,
	'an unrelated scholar cannot create a conflict'
);

-- The other venue's admin cannot create a conflict on this venue's submission.
select tests.authenticate_as(:'other_admin');
select throws_ok(
	$$ insert into public.conflicts (submissionid, scholarid, reason)
	   values ( $$ || quote_literal(:'sub') || $$, $$ || quote_literal(:'author') || $$, 'wrong venue' ) $$,
	'42501',
	null,
	'an admin of a different venue cannot create a conflict here'
);

-- ---- UPDATE -------------------------------------------------------------------
-- A venue admin can update a conflict on their submission.
select tests.authenticate_as(:'vadmin');
select lives_ok(
	$$ update public.conflicts set reason = 'updated by admin'
	   where submissionid = $$ || quote_literal(:'sub') || $$ and scholarid = $$ || quote_literal(:'author'),
	'a venue admin can update a conflict'
);
select tests.clear_authentication();
select is(
	(select reason from public.conflicts where submissionid = :'sub' and scholarid = :'author'),
	'updated by admin',
	'the conflict reason was updated'
);

-- A non-admin UPDATE is filtered by the using clause (0 rows, no error); the row
-- must remain unchanged.
select tests.authenticate_as(:'outsider');
update public.conflicts set reason = 'tampered'
	where submissionid = :'sub' and scholarid = :'author';
select tests.clear_authentication();
select is(
	(select reason from public.conflicts where submissionid = :'sub' and scholarid = :'author'),
	'updated by admin',
	'a non-admin cannot update a conflict (no-op)'
);

-- ---- DELETE -------------------------------------------------------------------
-- A non-admin DELETE is filtered by the using clause (0 rows, no error); the row
-- must still be present.
select tests.authenticate_as(:'outsider');
delete from public.conflicts where submissionid = :'sub' and scholarid = :'author';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.conflicts where submissionid = :'sub' and scholarid = :'author'),
	1,
	'a non-admin cannot delete a conflict'
);

-- A volunteer for the venue is still not an admin, so cannot delete either.
select tests.authenticate_as(:'volunteer');
delete from public.conflicts where submissionid = :'sub' and scholarid = :'author';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.conflicts where submissionid = :'sub' and scholarid = :'author'),
	1,
	'a volunteer cannot delete a conflict'
);

-- A venue admin can delete a conflict on their submission.
select tests.authenticate_as(:'vadmin');
select lives_ok(
	$$ delete from public.conflicts
	   where submissionid = $$ || quote_literal(:'sub') || $$ and scholarid = $$ || quote_literal(:'author'),
	'a venue admin can delete a conflict'
);

select * from finish();
rollback;
