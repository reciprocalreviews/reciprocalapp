-- Make a database safe to restore INTO. Run this first, always, including in
-- drills — before any data is loaded.
--
--     psql "$DB_URL" -f supabase/dr/quarantine.sql
--
-- A restore is not just a data operation. This schema reaches out into the world
-- on write, and several of those reaches are pointed at real people:
--
--   1. Inserting a row into `emails` sends mail. The send_on_email_insert trigger
--      posts every row to the `resend` edge function. Restoring the emails table
--      with that trigger live re-sends the entire history of notifications.
--   2. `cron.job` carries the remind-daily schedule, which mails scholars about
--      stale availability and admins about pending transactions. A restored clone
--      starts doing that on its own.
--   3. The realtime publication fans every restored row out to every connected
--      client, each firing invalidateAll().
--
-- This script neutralizes all three and records exactly what it changed, so
-- rearm.sql can put it back without relying on a hardcoded list that silently
-- goes stale when someone adds a table to the publication.
--
-- IT DOES NOT DISABLE THE LOGGING TRIGGERS, AND IT DOES NOT NEED TO. Load data
-- with `session_replication_role = replica` in the same session (see RECOVERY.md).
-- That suppresses every user trigger at once, which matters more than it looks:
-- without it, restoring N rows manufactures N audit_log and token_events entries
-- dated today, corrupting the very history you are restoring.
--------------------------------------
begin;

-- Everything this script learns is kept here so rearm.sql can reverse it exactly.
-- Dropped by rearm at the end of the restore.
--
-- Inserts are `on conflict do nothing`, so the FIRST capture wins. That matters:
-- this script may legitimately run twice — once by hand before you destroy
-- anything, and again from drill.sh — and by the second run the tables are gone,
-- so a re-capture would record an EMPTY publication and rearm would rebuild
-- nothing. Preserving the earliest state is the whole point.
-- Lives in its own schema, NOT in `public`. A restore very often begins with
-- `drop schema public cascade`, which would take this record with it — losing
-- exactly the publication membership rearm needs, since the dump does not carry
-- it either. `dr` survives both the drop and the restore.
create schema if not exists dr;

create table if not exists dr.quarantine_state (
	key text primary key,
	value jsonb not null,
	recorded_at timestamptz not null default now()
);

-- ---- 1. Outbound mail ---------------------------------------------------------
insert into dr.quarantine_state (key, value)
select
	'email_trigger_enabled',
	to_jsonb(count(*) > 0)
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
where c.relname = 'emails'
	and t.tgname = 'send_on_email_insert'
	and t.tgenabled <> 'D'
on conflict (key) do nothing;

alter table public.emails disable trigger send_on_email_insert;

-- ---- 2. Scheduled jobs ---------------------------------------------------------
-- cron.job lives outside every schema dump, which is how remind-daily was lost
-- once already (see migration 20260517230819_restore_remind_cron.sql). Capture
-- the full definition, not just the name, so rearm can recreate it verbatim.
insert into dr.quarantine_state (key, value)
select 'cron_jobs', coalesce(jsonb_agg(jsonb_build_object(
	'jobname', jobname, 'schedule', schedule, 'command', command
)), '[]'::jsonb)
from cron.job
on conflict (key) do nothing;

do $$
declare _j record;
begin
	for _j in select jobname from cron.job where jobname is not null loop
		perform cron.unschedule(_j.jobname);
	end loop;
end;
$$;

-- ---- 3. Realtime fanout --------------------------------------------------------
insert into dr.quarantine_state (key, value)
select 'realtime_tables', coalesce(jsonb_agg(
	format('%s.%s', schemaname, tablename) order by schemaname, tablename
), '[]'::jsonb)
from pg_publication_tables
where pubname = 'supabase_realtime'
on conflict (key) do nothing;

drop publication if exists supabase_realtime;

-- ---- 4. Vault ------------------------------------------------------------------
-- Names only. The VALUES are deliberately never captured anywhere — not here, not
-- in a backup — because they are set by hand and belong in a password manager.
insert into dr.quarantine_state (key, value)
select 'vault_secret_names', coalesce(jsonb_agg(name order by name), '[]'::jsonb)
from vault.secrets
on conflict (key) do nothing;

commit;

--------------------------------------
-- Report
select
	'email trigger'  as control, (select value from dr.quarantine_state where key = 'email_trigger_enabled')::text || ' -> disabled' as state
union all select
	'cron jobs',      (select jsonb_array_length(value) from dr.quarantine_state where key = 'cron_jobs')::text || ' recorded -> unscheduled'
union all select
	'realtime tables',(select jsonb_array_length(value) from dr.quarantine_state where key = 'realtime_tables')::text || ' recorded -> publication dropped'
union all select
	'vault secrets',  (select jsonb_array_length(value) from dr.quarantine_state where key = 'vault_secret_names')::text || ' names recorded (values untouched)';

\echo ''
\echo 'Quarantined. Load data with session_replication_role = replica, then run rearm.sql.'
\echo ''
\echo 'OPTIONAL, and DESTRUCTIVE: blanking the vault secrets makes send_email() take'
\echo 'its raise-warning path even if the trigger is somehow re-enabled. It is a'
\echo 'second line of defence, but the values are in no backup and cannot be'
\echo 'recovered by this script — you must be able to re-enter them by hand. Only'
\echo 'run this if you have them in front of you:'
\echo ''
\echo "    select vault.update_secret(id, '') from vault.secrets;"
\echo ''
