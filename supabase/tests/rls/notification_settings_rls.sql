-- RLS tests for public.notification_settings.
--
-- Authorization model under test:
--   SELECT  the scholar themselves, and nobody else. Deliberately NOT public, unlike the
--           rest of a scholar's metadata ("Scholar metadata is public" selects using
--           (true)): which notices someone has silenced is nobody else's business, and
--           keeping it private is the whole reason this is a table rather than a column on
--           the world-readable scholars row.
--   INSERT  the scholar themselves, for their own row only.
--   UPDATE  the scholar themselves, on their own row, and they cannot hand the row to
--           anyone else — the WITH CHECK is what stops that. There is deliberately no
--           column-level boundary here, unlike scholars and volunteers: every column is
--           part of "which of my own preferences this is", so repointing `event` reaches
--           nothing a plain insert could not.
--   DELETE  the scholar themselves. Deleting restores the default, which is on.
--
-- Absence of a row IS the default, so there is nothing to test about a scholar who has
-- never touched a setting: they receive everything, which is what the rpc tests cover.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan (8);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('ns_self@test.local')     as self     \gset
select tests.create_scholar('ns_other@test.local')    as other    \gset

insert into public.notification_settings (scholar, event, enabled)
values (:'other', 'NewVolunteer', false);

-- ---- The scholar's own row ----------------------------------------------------
select tests.authenticate_as(:'self');

select lives_ok(
	format($$ insert into public.notification_settings (scholar, event, enabled) values (%L::uuid, 'NewVolunteer', false) $$, :'self'),
	'a scholar can silence a notice for themselves'
);

select lives_ok(
	format($$ update public.notification_settings set enabled = true where scholar = %L::uuid $$, :'self'),
	'a scholar can turn one of their own notices back on'
);

-- The real boundary: USING lets them touch the row, WITH CHECK refuses to let it land on
-- somebody else. Without that, "edit my own preference" would be a way to write anyone's.
select throws_ok(
	format($$ update public.notification_settings set scholar = %L::uuid where scholar = %L::uuid $$, :'other', :'self'),
	'42501',
	null,
	'a scholar cannot hand their own setting to another scholar'
);

select lives_ok(
	format($$ delete from public.notification_settings where scholar = %L::uuid $$, :'self'),
	'a scholar can clear their own setting, restoring the default'
);

-- ---- Somebody else's ----------------------------------------------------------
-- Not "denied" but "invisible": a row the policy filters out is simply not there, so a
-- scholar cannot even learn that someone has silenced something.
select is(
	(select count(*)::int from public.notification_settings where scholar = :'other'),
	0,
	'another scholar''s notification settings are invisible'
);

select throws_ok(
	format($$ insert into public.notification_settings (scholar, event, enabled) values (%L::uuid, 'RoleInvite', false) $$, :'other'),
	'42501',
	null,
	'a scholar cannot set a preference on another scholar''s behalf'
);

-- Filtered rather than refused: the USING clause removes the row, so the update matches
-- nothing and the other scholar's preference stands.
select lives_ok(
	format($$ update public.notification_settings set enabled = true where scholar = %L::uuid $$, :'other'),
	'updating another scholar''s setting affects no rows'
);

select tests.clear_authentication();
select is(
	(select enabled from public.notification_settings where scholar = :'other' and event = 'NewVolunteer'),
	false,
	'and the other scholar''s preference is unchanged'
);

select * from finish();
rollback;
