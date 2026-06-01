-- RLS tests for public.volunteers.
--
-- Authorization model under test:
--   SELECT  anyone (authenticated + anon).
--   INSERT  venue admins (of the role's venue), OR the scholar themselves but
--           only when the role is NOT invite-only (roles.invited = false).
--   UPDATE  the volunteering scholar only.
--   DELETE  venue admins OR the volunteering scholar.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('vol_minter@test.local') as minter \gset
select tests.create_scholar('vol_admin@test.local') as vadmin \gset
select tests.create_scholar('vol_self@test.local') as self \gset
select tests.create_scholar('vol_other@test.local') as other \gset
select tests.create_scholar('vol_outsider@test.local') as outsider \gset
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
-- admins must NOT overlap the currency's minters → distinct scholars.
select tests.create_venue(:'cur', array[:'vadmin']::uuid[]) as ven \gset

-- An open (not invite-only) role and an invite-only role at the same venue.
select tests.create_role(:'ven', 0, null, false, false) as open_role \gset
select tests.create_role(:'ven', 0, null, false, true) as invite_role \gset

-- Pre-existing volunteer rows for read / update / delete probes.
select tests.create_volunteer(:'self', :'open_role') as vol_self \gset
select tests.create_volunteer(:'other', :'open_role') as vol_other \gset
select tests.create_volunteer(:'self', :'open_role') as vol_del_self \gset
select tests.create_volunteer(:'other', :'open_role') as vol_del_admin \gset
select tests.create_volunteer(:'other', :'open_role') as vol_del_denied \gset

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'volunteers',
	array[
		'anyone can view volunteers',
		'admins can invite and volunteers if not invite only',
		'volunteers can update',
		'admins and volunteers can delete'
	]
);

-- ---- SELECT -------------------------------------------------------------------
select tests.authenticate_as(:'outsider');
select isnt_empty(
	$$ select 1 from public.volunteers where id = $$ || quote_literal(:'vol_self'),
	'an unrelated authenticated scholar can view volunteers'
);

select tests.authenticate_as_anon();
select isnt_empty(
	$$ select 1 from public.volunteers where id = $$ || quote_literal(:'vol_self'),
	'an anonymous visitor can view volunteers'
);

-- ---- INSERT -------------------------------------------------------------------
-- A venue admin may add anyone to a role (even an invite-only one).
select tests.authenticate_as(:'vadmin');
select lives_ok(
	$$ insert into public.volunteers (scholarid, roleid, expertise)
	   values ( $$ || quote_literal(:'other') || $$, $$ || quote_literal(:'invite_role') || $$, '' ) $$,
	'a venue admin can add a scholar to an invite-only role'
);

-- A scholar may volunteer themselves for an open (not invite-only) role.
select tests.authenticate_as(:'self');
select lives_ok(
	$$ insert into public.volunteers (scholarid, roleid, expertise)
	   values ( $$ || quote_literal(:'self') || $$, $$ || quote_literal(:'open_role') || $$, '' ) $$,
	'a scholar can self-volunteer for an open role'
);

-- A scholar may NOT volunteer themselves for an invite-only role.
select tests.authenticate_as(:'self');
select throws_ok(
	$$ insert into public.volunteers (scholarid, roleid, expertise)
	   values ( $$ || quote_literal(:'self') || $$, $$ || quote_literal(:'invite_role') || $$, '' ) $$,
	'42501',
	null,
	'a scholar cannot self-volunteer for an invite-only role'
);

-- A scholar may NOT volunteer someone else (even for an open role).
select tests.authenticate_as(:'self');
select throws_ok(
	$$ insert into public.volunteers (scholarid, roleid, expertise)
	   values ( $$ || quote_literal(:'other') || $$, $$ || quote_literal(:'open_role') || $$, '' ) $$,
	'42501',
	null,
	'a non-admin scholar cannot volunteer someone else'
);

-- ---- UPDATE -------------------------------------------------------------------
-- The volunteering scholar may update their own row.
select tests.authenticate_as(:'self');
select lives_ok(
	$$ update public.volunteers set expertise = 'mine' where id = $$ || quote_literal(:'vol_self'),
	'a scholar can update their own volunteer record'
);
select tests.clear_authentication();
select is(
	(select expertise from public.volunteers where id = :'vol_self'),
	'mine',
	'the volunteer record reflects the self-update'
);

-- A different scholar's UPDATE is filtered by the using clause (0 rows, no error).
select tests.authenticate_as(:'other');
update public.volunteers set expertise = 'tampered' where id = :'vol_self';
select tests.clear_authentication();
select is(
	(select expertise from public.volunteers where id = :'vol_self'),
	'mine',
	'another scholar cannot update someone else''s volunteer record (no-op)'
);

-- A venue admin cannot update a volunteer row they do not own (using = self only).
select tests.authenticate_as(:'vadmin');
update public.volunteers set expertise = 'admin-edit' where id = :'vol_self';
select tests.clear_authentication();
select is(
	(select expertise from public.volunteers where id = :'vol_self'),
	'mine',
	'a venue admin cannot update a volunteer record (no-op)'
);

-- ---- DELETE -------------------------------------------------------------------
-- The volunteering scholar may delete their own row.
select tests.authenticate_as(:'self');
select lives_ok(
	$$ delete from public.volunteers where id = $$ || quote_literal(:'vol_del_self'),
	'a scholar can delete their own volunteer record'
);

-- A venue admin may delete a volunteer row at their venue.
select tests.authenticate_as(:'vadmin');
select lives_ok(
	$$ delete from public.volunteers where id = $$ || quote_literal(:'vol_del_admin'),
	'a venue admin can delete a volunteer record at their venue'
);

-- An unrelated scholar cannot delete (using filters → 0 rows, no error).
select tests.authenticate_as(:'outsider');
delete from public.volunteers where id = :'vol_del_denied';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.volunteers where id = :'vol_del_denied'),
	1,
	'an unrelated scholar cannot delete a volunteer record'
);

select * from finish();
rollback;
