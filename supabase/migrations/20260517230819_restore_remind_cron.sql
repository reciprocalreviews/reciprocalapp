-- pg_cron must remain enabled — see supabase/functions/remind/index.ts.
-- It was accidentally dropped by a `supabase db diff` run in
-- 20260201193327_submission_edits.sql, taking the reminder schedule with it.
create extension if not exists "pg_cron" with schema "pg_catalog";

-- Unschedule the legacy job name if anything left a stub behind, then re-add.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'remind-weekly') then
    perform cron.unschedule('remind-weekly');
  end if;
  if exists (select 1 from cron.job where jobname = 'remind-daily') then
    perform cron.unschedule('remind-daily');
  end if;
end $$;

-- Fire daily at 22:00 UTC. The edge function applies per-venue gating using
-- venues.transaction_reminder_frequency_days and transaction_reminder_time.
select cron.schedule (
  'remind-daily',
    '0 22 * * *',
    $$
    select
      net.http_post(
        url:=replace(private.get_secret('supabase_url'), '127.0.0.1', 'host.docker.internal') || '/functions/v1/remind',
        headers:=jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || private.get_secret('anon_key')
        )::jsonb,
        body:=jsonb_build_object()
       );
    $$
);
