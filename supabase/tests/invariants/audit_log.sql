-- Behavioural tests for public.audit_log.
--
-- The properties that matter:
--   1. Inserts, updates, and deletes are all captured, with both sides of the
--      change where both exist.
--   2. No-op updates are not captured, or the log fills with noise.
--   3. The identity of the changed row is recoverable, including for the two
--      tables whose primary key is composite.
--   4. The latest payload for a row equals that row — which is the replay
--      property a restore-then-catch-up depends on.
--   5. The deliberately excluded tables really are excluded.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

select tests.clear_authentication();
select tests.create_scholar('al_minter@test.local') as minter \gset
select tests.create_scholar('al_admin@test.local') as admin \gset
select tests.create_scholar('al_other@test.local') as other \gset
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset
select tests.create_role(:'ven', 0) as role \gset
select tests.create_submission_type(:'ven') as stype \gset

-- ---- 1. INSERT ----------------------------------------------------------------
select is(
	(select count(*)::int from public.audit_log
		where tbl = 'venues' and op = 'INSERT' and row_id = :'ven'
			and before is null and after is not null),
	1,
	'an insert is captured with an after payload and no before'
);

-- ---- 2. UPDATE ----------------------------------------------------------------
update public.venues set title = 'Renamed Venue' where id = :'ven';

select is(
	(select count(*)::int from public.audit_log
		where tbl = 'venues' and op = 'UPDATE' and row_id = :'ven'
			and before ->> 'title' = 'Test Venue'
			and after ->> 'title' = 'Renamed Venue'),
	1,
	'an update is captured with both the old and the new value'
);

-- ---- 3. No-op updates are skipped ----------------------------------------------
-- The app calls invalidateAll() after every write and several components re-save
-- unchanged values, so this is the difference between a usable log and noise.
update public.venues set title = 'Renamed Venue' where id = :'ven';

select is(
	(select count(*)::int from public.audit_log
		where tbl = 'venues' and op = 'UPDATE' and row_id = :'ven'),
	1,
	'an update that changes nothing is not recorded'
);

-- ---- 4. DELETE -----------------------------------------------------------------
-- The most important case: after this, the row exists nowhere else.
delete from public.submission_types where id = :'stype';

select is(
	(select count(*)::int from public.audit_log
		where tbl = 'submission_types' and op = 'DELETE' and row_id = :'stype'
			and before is not null and after is null),
	1,
	'a delete is captured with the row it destroyed'
);

-- ---- 5. Composite-PK tables ----------------------------------------------------
-- compensation keys on (submission_type, role), so row_id is null — but the
-- identity must still be recoverable from the payload.
select tests.create_submission_type(:'ven') as stype2 \gset
insert into public.compensation (submission_type, role, amount, rationale)
values (:'stype2', :'role', 5, 'test');

select is(
	(select count(*)::int from public.audit_log
		where tbl = 'compensation' and op = 'INSERT'
			and row_id is null
			and after ->> 'submission_type' = :'stype2'
			and after ->> 'role' = :'role'),
	1,
	'a composite-key row has no row_id but is still identifiable from its payload'
);

-- ---- 6. Replay: the latest payload equals the row ------------------------------
-- This is the property a restore-then-catch-up rests on: applying each `after` in
-- seq order reproduces the table. Checked here for every venue that has history.
select is(
	(select count(*)::int
		from public.venues v
		join lateral (
			select a.after
			from public.audit_log a
			where a.tbl = 'venues' and a.row_id = v.id and a.op <> 'DELETE'
			order by a.seq desc
			limit 1
		) latest on true
		where latest.after is distinct from to_jsonb(v)),
	0,
	'the most recent payload for each row equals that row exactly'
);

-- ---- 7. Attribution ------------------------------------------------------------
select tests.authenticate_as(:'admin');
update public.venues set description = 'edited by the admin' where id = :'ven';
select tests.clear_authentication();

select is(
	(select actor from public.audit_log
		where tbl = 'venues' and row_id = :'ven' and after ->> 'description' = 'edited by the admin'
		order by seq desc limit 1),
	:'admin'::uuid,
	'the acting scholar is recorded'
);

-- ---- 8. Coverage ---------------------------------------------------------------
select is(
	(select count(*)::int from pg_trigger t
		join pg_class c on c.oid = t.tgrelid
		join pg_namespace n on n.oid = c.relnamespace
		where n.nspname = 'public' and t.tgname like '%\_audit' and not t.tgisinternal),
	16,
	'all sixteen audited tables carry the trigger'
);

-- tokens is covered by token_events instead; emails is already immutable and
-- would duplicate every message body; email_verifications holds a token hash.
select is(
	(select count(*)::int from pg_trigger t
		join pg_class c on c.oid = t.tgrelid
		join pg_namespace n on n.oid = c.relnamespace
		where n.nspname = 'public'
			and c.relname in ('tokens', 'emails', 'email_verifications', 'token_events', 'audit_log')
			and t.tgname like '%\_audit' and not t.tgisinternal),
	0,
	'the deliberately excluded tables are not audited'
);

select * from finish();
rollback;
