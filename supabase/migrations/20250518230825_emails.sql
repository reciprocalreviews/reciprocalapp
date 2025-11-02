-- The emails table is a log of all emails sent to scholars.
create table emails (
  -- The unique ID of the bid, automatically generated
  id uuid not null default gen_random_uuid() primary key,
  -- The event type of the email
  event text not null,
  -- The optional scholar to whom the email was sent
  scholar uuid references scholars(id),
  -- The optional venue for which the email was sent
  venue uuid references venues(id) default null,
  -- When the email was sent
  time_sent timestamp with time zone not null default now(),
  -- The email to whom the email was sent
  email text not null,
  -- The subject of the email
  subject text not null,
  -- The body of the email
  message text not null
);

-- Make it fast to retrieve the assignments of a scholar.
create index emails_scholar_index on emails(scholar);
create index emails_venue_index on emails(venue);

-- Enable RLS for emails
alter table public.emails
  enable row level security;

-- Anyone authenticated can send an email.
create policy "authenticated scholars can send email" on public.emails
  for insert to authenticated with check (true);

-- Scholars can see the emails sent to them; venue editors can see all emails sent by the venue.
create policy "scholars and venue editors can see the emails sent" on public.emails
  for select to anon, authenticated using (
    ((select auth.uid()) = scholar) or
    (venue is not null and isEditor(venue))
  );

-- No one can edit emails once sent.
create policy "emails can't be edited" on public.emails
  for update to anon, authenticated 
using (false);

-- No one can delete emails once sent.
create policy "emails can't be deleted" on public.emails
  for delete to authenticated 
  using (false);

-- Create a schema to store this private function that gets a vault secret.
create schema private; -- to avoid this function in the API

create or replace function private.get_secret (secret_name text)
returns text
security definer
set search_path = ''
as
$$ 
declare
   secret text;
begin
   select decrypted_secret into secret from vault.decrypted_secrets where name = secret_name;
   return secret;
end;
$$ language plpgsql;

-- Create a function that sends the new email.
create or replace function send_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Post to the Resend edge function. If the supabase URL is set to localhost, replace it with host.docker.internal so we hit the host machine, not the container.
  perform net.http_post(
    url:=replace(private.get_secret('supabase_url'), '127.0.0.1', 'host.docker.internal') || '/functions/v1/resend',
    headers:=jsonb_build_object(
        'Content-Type', 'application/json', 
        'Authorization', 'Bearer ' || private.get_secret('anon_key')
    )::jsonb,
    body:=jsonb_build_object('to', new.email, 'subject', new.subject, 'message', new.message)
  );
  return new;
end;
$$;

-- When there's a new email, send it.
create trigger "send_on_email_insert"
after insert on public.emails
for each row
execute function send_email();