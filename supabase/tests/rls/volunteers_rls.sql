-- RLS tests for public.volunteers.
--
-- Authorization model under test:
--   SELECT  anyone (authenticated + anon).
--   INSERT  venue admins (of the role's venue), OR the scholar themselves but
--           only when the role is NOT invite-only (roles.invited = false).
--   UPDATE  the volunteering scholar only, and only the columns active,
--           expertise and papers — the table privilege is revoked and re-granted
--           per column, so writing scholarid/roleid/accepted raises 42501.
--   DELETE  no one (denied by policy AND the table privilege is revoked, so an
--           attempt raises 42501 rather than quietly affecting 0 rows).

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

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

-- A second venue, for the cross-venue repoint probe below. Its admin and minter
-- are distinct scholars, as at :ven, so no_minter_admins does not fire.
select tests.create_scholar('vol_minter2@test.local') as minter2 \gset
select tests.create_scholar('vol_admin2@test.local') as vadmin2 \gset
select tests.create_currency(array[:'minter2']::uuid[]) as cur2 \gset
select tests.create_venue(:'cur2', array[:'vadmin2']::uuid[]) as ven2 \gset
select tests.create_role(:'ven2', 0, null, false, false) as open_role2 \gset

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
		'volunteers cannot be deleted'
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

-- Identity columns are not writable. Repointing roleid moves the row to another
-- venue, dropping the scholar's count at the original one to zero — which is the
-- count create_volunteer uses to decide the welcome grant. The privilege is
-- revoked per column, so the attempt raises rather than quietly succeeding.
select tests.authenticate_as(:'self');
select throws_ok(
	$$ update public.volunteers set roleid = $$ || quote_literal(:'open_role2')
		|| $$ where id = $$ || quote_literal(:'vol_self'),
	'42501',
	null,
	'a scholar cannot repoint their volunteer record to another venue''s role'
);

select throws_ok(
	$$ update public.volunteers set scholarid = $$ || quote_literal(:'other')
		|| $$ where id = $$ || quote_literal(:'vol_self'),
	'42501',
	null,
	'a scholar cannot hand their volunteer record to another scholar'
);

-- The granted columns still work: unvolunteering is a toggle of active, and it
-- is the whole reason the row survives at all.
select lives_ok(
	$$ update public.volunteers set active = false where id = $$ || quote_literal(:'vol_self'),
	'a scholar can still deactivate their own volunteer record'
);

-- ---- DELETE -------------------------------------------------------------------
-- Nobody deletes a volunteer record. The table privilege is revoked, not merely
-- denied by policy, so every client DELETE fails with 42501 — including the two
-- roles the old policy admitted, the volunteering scholar and the venue admin.
select tests.authenticate_as(:'self');
select throws_ok(
	$$ delete from public.volunteers where id = $$ || quote_literal(:'vol_del_self'),
	'42501',
	null,
	'a scholar cannot delete their own volunteer record'
);

select tests.authenticate_as(:'vadmin');
select throws_ok(
	$$ delete from public.volunteers where id = $$ || quote_literal(:'vol_del_admin'),
	'42501',
	null,
	'a venue admin cannot delete a volunteer record at their venue'
);

select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ delete from public.volunteers where id = $$ || quote_literal(:'vol_del_denied'),
	'42501',
	null,
	'an unrelated scholar cannot delete a volunteer record'
);

select tests.clear_authentication();
select is(
	(select count(*)::int from public.volunteers
		where id in (:'vol_del_self', :'vol_del_admin', :'vol_del_denied')),
	3,
	'every volunteer record survives the deletion attempts'
);

-- ---- The definer path is unaffected -------------------------------------------
-- accept_role_invite writes `accepted`, a column authenticated no longer holds
-- UPDATE on. It is SECURITY DEFINER and owned by postgres, so the revoke does
-- not reach it — which is the assumption this whole change rests on: clients
-- lose the direct write, the RPCs keep it.
select tests.clear_authentication();
select tests.create_volunteer(:'self', :'invite_role', 'invited') as vol_invite \gset
select tests.authenticate_as(:'self');
select lives_ok(
	$$ select public.accept_role_invite( $$ || quote_literal(:'vol_invite') || $$, 'accepted' ) $$,
	'accept_role_invite still writes accepted after the column privilege is revoked'
);
select tests.clear_authentication();
select is(
	(select accepted::text from public.volunteers where id = :'vol_invite'),
	'accepted',
	'the invitation response was recorded through the definer path'
);

select * from finish();
rollback;
