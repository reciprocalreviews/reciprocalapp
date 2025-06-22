create extension if not exists "pg_cron" with schema "pg_catalog";

select cron.schedule (
  'remind-weekly',
    -- Every 30 seconds, for testing '30 seconds'
    -- Every Sunday at 10 pm
    '0 22 * * 7',
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

-- Add a column to remember when the scholar updated their status.
alter table scholars
add status_time timestamp with time zone;
alter table scholars
add status_reminder_time timestamp with time zone;