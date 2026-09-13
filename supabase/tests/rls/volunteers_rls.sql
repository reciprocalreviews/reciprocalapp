-- RLS tests for public.volunteers.
--
-- Authorization model under test:
--   SELECT  governed by the role's volunteer_visibility setting, with four ways
--           past it. A viewer sees a volunteer record if it is their OWN; or the
--           role is invite-only or at priority 0 (both are status nobody can award
--           themselves, so both stay public); or the viewer staffs the role (a
--           venue admin, a priority-0 editor, or a holder of the role's approver);
--           or the setting allows it -- 'all' always, 'completed' only for a
--           scholar with a completed assignment ANYWHERE at that venue, 'none'
--           never. public.venue_volunteer_counts reports true per-role counts
--           regardless, so hiding a roster never hides its size.
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
select plan(37);

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
-- are distinct scholars, as at :ven, so nothing here turns on the overlap.
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
		'volunteer visibility follows the role''s setting',
		'admins can invite and volunteers if not invite only',
		'volunteers can update',
		'volunteers cannot be deleted'
	]
);

-- ---- SELECT -------------------------------------------------------------------
select tests.authenticate_as(:'outsider');
select isnt_empty(
	$$ select 1 from public.volunteers where id = $$ || quote_literal(:'vol_self'),
	'an unrelated authenticated scholar can view volunteers of an unrestricted role'
);

select tests.authenticate_as_anon();
select isnt_empty(
	$$ select 1 from public.volunteers where id = $$ || quote_literal(:'vol_self'),
	'an anonymous visitor can view volunteers of an unrestricted role'
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

-- ---- Volunteer visibility -----------------------------------------------------
-- Fixtures for the setting. A venue with an editor role at priority 0, an
-- approver role, and the role under test approved by it -- so every branch of the
-- predicate has someone who exercises it and someone who does not.
select tests.clear_authentication();
select tests.create_scholar('vis_minter@test.local') as vminter \gset
select tests.create_scholar('vis_admin@test.local') as vis_admin \gset
select tests.create_scholar('vis_editor@test.local') as vis_editor \gset
select tests.create_scholar('vis_approver@test.local') as vis_approver \gset
select tests.create_scholar('vis_bystander@test.local') as vis_bystander \gset
select tests.create_scholar('vis_listed@test.local') as vis_listed \gset
select tests.create_scholar('vis_unlisted@test.local') as vis_unlisted \gset
select tests.create_currency(array[:'vminter']::uuid[]) as vis_cur \gset
select tests.create_venue(:'vis_cur', array[:'vis_admin']::uuid[]) as vis_ven \gset

-- Priority 0 is the venue's editor role; the approver role sits below it.
select tests.create_role(:'vis_ven', 0, null, false, false) as vis_editor_role \gset
select tests.create_role(:'vis_ven', 1, null, false, false) as vis_approver_role \gset
-- The role under test: open (not invite-only), below priority 0, approved by the
-- approver role. Visibility is flipped per probe.
select tests.create_role(:'vis_ven', 2, :'vis_approver_role', false, false, 'all') as vis_role \gset

select tests.create_volunteer(:'vis_editor', :'vis_editor_role') as vis_editor_vol \gset
select tests.create_volunteer(:'vis_approver', :'vis_approver_role') as vis_approver_vol \gset
select tests.create_volunteer(:'vis_listed', :'vis_role') as vis_listed_vol \gset
select tests.create_volunteer(:'vis_unlisted', :'vis_role') as vis_unlisted_vol \gset

-- A completed assignment for vis_listed, in a DIFFERENT role at the same venue.
-- That is what makes the 'completed' probes below a test of "anywhere at this
-- venue" rather than "in this role", which is the distinction the predicate draws
-- by joining assignments through public.roles.
select tests.create_scholar('vis_author@test.local') as vis_author \gset
select tests.create_submission_type(:'vis_ven') as vis_type \gset
select tests.create_submission(:'vis_ven', :'vis_type', array[:'vis_author']::uuid[]) as vis_sub \gset
select tests.create_assignment(
	:'vis_ven', :'vis_sub', :'vis_listed', :'vis_approver_role', true, false, true
) as vis_done \gset

--    'all' -- today's behaviour, and the default.
select tests.authenticate_as_anon();
select is(
	(select count(*)::int from public.volunteers where roleid = :'vis_role'),
	2,
	'at ''all'', an anonymous visitor sees the whole roster'
);

--    'none' -- nobody outside the people who staff the role.
select tests.clear_authentication();
update public.roles set volunteer_visibility = 'none' where id = :'vis_role';

select tests.authenticate_as_anon();
select is_empty(
	$$ select 1 from public.volunteers where roleid = $$ || quote_literal(:'vis_role'),
	'at ''none'', an anonymous visitor sees nobody'
);

select tests.authenticate_as(:'vis_bystander');
select is_empty(
	$$ select 1 from public.volunteers where roleid = $$ || quote_literal(:'vis_role'),
	'at ''none'', an unrelated signed-in scholar sees nobody'
);

-- The self branch. Load-bearing well beyond courtesy: the submissions SELECT
-- policy and the assignments INSERT policy both read public.volunteers inline and
-- are therefore gated by this policy, and both filter to auth.uid().
select tests.authenticate_as(:'vis_listed');
select is(
	(select count(*)::int from public.volunteers where roleid = :'vis_role'),
	1,
	'at ''none'', a volunteer still sees their own record and no one else''s'
);

select tests.authenticate_as(:'vis_admin');
select is(
	(select count(*)::int from public.volunteers where roleid = :'vis_role'),
	2,
	'at ''none'', a venue admin sees the whole roster'
);

select tests.authenticate_as(:'vis_editor');
select is(
	(select count(*)::int from public.volunteers where roleid = :'vis_role'),
	2,
	'at ''none'', the venue''s priority-0 editor sees the whole roster'
);

select tests.authenticate_as(:'vis_approver');
select is(
	(select count(*)::int from public.volunteers where roleid = :'vis_role'),
	2,
	'at ''none'', a holder of the approving role sees the whole roster'
);

--    'completed' -- only the people who have done work at this venue.
select tests.clear_authentication();
update public.roles set volunteer_visibility = 'completed' where id = :'vis_role';

select tests.authenticate_as_anon();
select is(
	(select count(*)::int from public.volunteers where roleid = :'vis_role'),
	1,
	'at ''completed'', an anonymous visitor sees only the contributor'
);
select is(
	(select scholarid from public.volunteers where roleid = :'vis_role'),
	:'vis_listed'::uuid,
	'and the one they see completed an assignment in ANOTHER role at this venue'
);

-- An assignment that is approved but not completed does not earn a listing: the
-- tier is about finished work, and bulk-imported history lands approved-not-done.
select tests.clear_authentication();
select tests.create_assignment(
	:'vis_ven', :'vis_sub', :'vis_unlisted', :'vis_approver_role', true, false, false
) as vis_open \gset
select tests.authenticate_as_anon();
select is(
	(select count(*)::int from public.volunteers where roleid = :'vis_role'),
	1,
	'an approved but uncompleted assignment does not earn a listing'
);

-- A completed assignment at a DIFFERENT venue must not count, or the tier would
-- mean "has ever finished anything anywhere" rather than "has contributed here".
select tests.clear_authentication();
select tests.create_scholar('vis_minter2@test.local') as vminter2 \gset
select tests.create_scholar('vis_admin2@test.local') as vis_admin2 \gset
select tests.create_currency(array[:'vminter2']::uuid[]) as vis_cur2 \gset
select tests.create_venue(:'vis_cur2', array[:'vis_admin2']::uuid[]) as vis_ven2 \gset
select tests.create_role(:'vis_ven2', 0, null, false, false) as vis_role2 \gset
select tests.create_submission_type(:'vis_ven2') as vis_type2 \gset
select tests.create_submission(:'vis_ven2', :'vis_type2', array[:'vis_author']::uuid[]) as vis_sub2 \gset
select tests.create_assignment(
	:'vis_ven2', :'vis_sub2', :'vis_unlisted', :'vis_role2', true, false, true
) as vis_elsewhere \gset

select tests.authenticate_as_anon();
select is(
	(select count(*)::int from public.volunteers where roleid = :'vis_role'),
	1,
	'a completed assignment at another venue does not earn a listing here'
);

-- ---- The two exemptions -------------------------------------------------------
-- Invite-only: the invitation IS the vetting, so the setting is inert.
select tests.clear_authentication();
select tests.create_role(:'vis_ven', 3, null, false, true, 'none') as vis_invite_role \gset
select tests.create_volunteer(:'vis_unlisted', :'vis_invite_role') as vis_invite_vol \gset
select tests.authenticate_as_anon();
select isnt_empty(
	$$ select 1 from public.volunteers where roleid = $$ || quote_literal(:'vis_invite_role'),
	'an invite-only role publishes its volunteers even when set to ''none'''
);

-- Priority 0: the venue's editors are its public face, and -- less obviously --
-- SupabaseCRUD.emailEditorsOf resolves the editor mailing list by reading this
-- table with the CALLER's own session, from paths run by authors and reviewers.
select tests.clear_authentication();
update public.roles set volunteer_visibility = 'none' where id = :'vis_editor_role';
select tests.authenticate_as_anon();
select isnt_empty(
	$$ select 1 from public.volunteers where roleid = $$ || quote_literal(:'vis_editor_role'),
	'the venue''s priority-0 role publishes its volunteers even when set to ''none'''
);

-- ---- Counts survive the filter ------------------------------------------------
-- The interface still has to count rows the policy withholds. If this ever starts
-- reporting the filtered number, every count on the venue page silently becomes a
-- different statement for every reader.
select tests.clear_authentication();
update public.roles set volunteer_visibility = 'none' where id = :'vis_role';
select tests.authenticate_as_anon();
select is(
	(select volunteer_count from public.venue_volunteer_counts(:'vis_ven') where role = :'vis_role'),
	2,
	'venue_volunteer_counts reports the true count to an anonymous caller at ''none'''
);
select is(
	(select count(*)::int from public.venue_volunteer_counts(:'vis_ven')),
	4,
	'and returns one row per role at the venue, including roles with no volunteers'
);

-- ---- Regressions with teeth ---------------------------------------------------
-- Two OTHER tables' policies read public.volunteers inline, and an inline read in
-- a policy is gated by THAT table's policy -- this one. Both filter to auth.uid(),
-- so the self branch is what keeps them working. Each of these fails if that
-- branch is removed.
select tests.clear_authentication();
select tests.create_role(:'vis_ven', 4, null, true, false, 'none') as vis_bid_role \gset
select tests.create_volunteer(:'vis_bystander', :'vis_bid_role') as vis_bid_vol \gset

select tests.authenticate_as(:'vis_bystander');
select isnt_empty(
	$$ select 1 from public.submissions where id = $$ || quote_literal(:'vis_sub'),
	'an accepted volunteer on a biddable role still reads the venue''s submissions at ''none'''
);
select lives_ok(
	$$ insert into public.assignments (venue, submission, scholar, role, bid, approved)
	   values (
		$$ || quote_literal(:'vis_ven') || $$, $$ || quote_literal(:'vis_sub') || $$,
		$$ || quote_literal(:'vis_bystander') || $$, $$ || quote_literal(:'vis_bid_role') || $$,
		true, false
	   ) $$,
	'and can still bid on one at ''none'''
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
