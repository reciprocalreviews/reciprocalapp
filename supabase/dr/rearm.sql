-- Bring a restored database back to life. Run this LAST, and deliberately.
--
--     psql "$DB_URL" -f supabase/dr/rearm.sql
--
-- Reverses quarantine.sql from what that script recorded, rather than from a
-- hardcoded list — so adding a table to the realtime publication cannot silently
-- fall out of the recovery path.
--
-- Do not run this until the data is fully loaded and you have checked it against
-- the backup manifest. Re-arming a half-restored database points live email and a
-- daily cron at incomplete data.
--------------------------------------
\set ON_ERROR_STOP on

do $$
begin
	if to_regclass('dr.quarantine_state') is null then
		raise exception
			'No quarantine state found. Either quarantine.sql was never run, or rearm.sql already ran. Refusing to guess what to restore.';
	end if;
end;
$$;

begin;

-- ---- 1. Realtime ---------------------------------------------------------------
-- Rebuilt from what quarantine recorded. A restore into a fresh project that
-- never had the publication records an empty list, in which case the migrations
-- have already created it correctly and there is nothing to rebuild.
do $$
declare
	_tables text;
	_count int;
begin
	select jsonb_array_length(value) into _count
	from dr.quarantine_state where key = 'realtime_tables';

	if coalesce(_count, 0) = 0 then
		raise notice 'realtime: nothing recorded, leaving the publication as the schema created it';
	else
		if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
			raise notice 'realtime: publication already exists, leaving it alone';
		else
			-- The lateral is aliased because jsonb_array_elements' output column is
			-- also called `value`, which collides with dr_quarantine_state.value.
			select string_agg(e.v #>> '{}', ', ') into _tables
			from dr.quarantine_state s,
				lateral jsonb_array_elements(s.value) as e (v)
			where s.key = 'realtime_tables';
			execute format('create publication supabase_realtime for table %s', _tables);
			raise notice 'realtime: publication rebuilt with % tables', _count;
		end if;
	end if;
end;
$$;

-- ---- 2. Scheduled jobs ----------------------------------------------------------
do $$
declare _j jsonb;
begin
	for _j in
		select jsonb_array_elements(value)
		from dr.quarantine_state where key = 'cron_jobs'
	loop
		perform cron.schedule(_j ->> 'jobname', _j ->> 'schedule', _j ->> 'command');
		raise notice 'cron: rescheduled % (%)', _j ->> 'jobname', _j ->> 'schedule';
	end loop;
end;
$$;

-- ---- 3. Reminder suppression ----------------------------------------------------
-- Reminder de-duplication is stamped in the data: the remind function gates on
-- scholars.status_reminder_time and venues.transaction_reminder_time. Restoring to
-- a point before those stamps re-arms reminders that already went out, so the
-- next cycle would mail real people a second time.
--
-- Stamping everything costs at most one skipped cycle. Not stamping costs
-- duplicate mail to every affected scholar. The asymmetry is the whole argument;
-- if you would rather take the other side, comment these two statements out.
update public.scholars set status_reminder_time = now();

update public.venues set transaction_reminder_time = now();

-- ---- 4. Outbound mail -----------------------------------------------------------
-- Last, on purpose: everything above must be settled before this database is
-- able to send anything.
alter table public.emails enable trigger send_on_email_insert;

commit;

--------------------------------------
-- What still needs a human
select
	'vault' as needs,
	'set by hand; values are in no backup: ' ||
	coalesce((select string_agg(e.v #>> '{}', ', ')
		from dr.quarantine_state s, lateral jsonb_array_elements(s.value) as e (v)
		where s.key = 'vault_secret_names'), '(none recorded)') as detail
union all
select 'edge functions', 'supabase functions deploy resend && supabase functions deploy remind'
union all
select 'app config', 'point Vercel''s PUBLIC_SUPABASE_URL and keys at this project if it is a new one';

\echo ''
\echo 'Re-armed. Verify before declaring the restore done:'
\echo '  - row counts and watermarks against the backup manifest'
\echo '  - npm run test:rls  (proves policies, grants and column allowlists survived)'
\echo '  - select public.reconcile_ledger()  once that exists'
\echo ''
\echo 'Then, and only then, drop the quarantine record:'
\echo '    drop schema dr cascade;'
\echo ''
