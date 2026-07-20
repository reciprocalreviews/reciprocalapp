--------------------------------------
-- Schema
--
-- The emails table is a log of all emails sent to scholars.
create table if not exists public.emails (
	-- The unique ID of the bid, automatically generated
	id uuid default gen_random_uuid() not null,
	-- The event type of the email
	event text not null,
	-- The optional scholar to whom the email was sent
	scholar uuid,
	-- The optional scholar whose action sent the email (null for system-generated emails)
	sender uuid,
	-- The optional venue for which the email was sent
	venue uuid,
	-- When the email was sent
	time_sent timestamp with time zone default now() not null,
	-- The email to whom the email was sent
	email text not null,
	-- The subject of the email. Null when the row was queued by the database as an
	-- event + args to be rendered at send time (see `args` below).
	subject text,
	-- The body of the email. Null for the same reason as `subject`.
	message text,
	-- Template arguments for `event`, used when subject/message are null. Mail whose
	-- recipient is chosen by a caller must not also have its body chosen by that caller,
	-- so those rows carry structured args and the `resend` edge function renders them from
	-- supabase/functions/_shared/templates.ts at send time. event + args is a complete,
	-- re-renderable record of what was sent.
	args jsonb default '[]'::jsonb not null
);

alter table public.emails OWNER to "postgres";

grant all on table public.emails to "anon";

grant all on table public.emails to "authenticated";

grant all on table public.emails to "service_role";

alter table only public.emails
add constraint "emails_pkey" primary key (id);

alter table only public.emails
add constraint "emails_scholar_fkey" foreign KEY (scholar) references public.scholars (id);

alter table only public.emails
add constraint "emails_sender_fkey" foreign KEY (sender) references public.scholars (id);

alter table only public.emails
add constraint "emails_venue_fkey" foreign KEY (venue) references public.venues (id);

--------------------------------------
-- Indexes
--
create index emails_scholar_index on public.emails using btree (scholar);

create index emails_venue_index on public.emails using btree (venue);

--------------------------------------
-- Security
--
alter table public.emails ENABLE row LEVEL SECURITY;

create policy "senders, recipients, and venue admins can see the emails sent" on public.emails for
select
	to authenticated using (
		(
			(
				(
					select
						auth.uid () as uid
				)=scholar
			)
			or (
				(
					select
						auth.uid () as uid
				)=sender
			)
			or (
				(venue is not null)
				and public.isAdmin (venue)
			)
		)
	);

-- There is deliberately NO insert policy. The AFTER INSERT trigger below sends branded
-- mail, so a policy allowing authenticated inserts made this an open relay: any signed-in
-- user could name any recipient with any subject and body. Sending now goes through
-- public.queue_email (and public.request_email_verification), which resolve recipients
-- server-side and render the body from the template registry at send time. The privilege
-- is revoked too, so a direct attempt fails cleanly with 42501 rather than an empty result.
revoke insert on table public.emails
from
	authenticated,
	anon;

create policy "emails can't be edited" on public.emails
for update
	to authenticated using (false);

create policy "emails can't be deleted" on public.emails for DELETE to authenticated using (false);

--------------------------------------
-- Functions
--
-- Create a schema to store this private function that gets a vault secret.
create schema private;

-- to avoid this function in the API
create or replace function private.get_secret (secret_name text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER
set
	"search_path" to '' as $$ 
declare
   secret text;
begin
   select decrypted_secret into secret from vault.decrypted_secrets where name = secret_name;
   return secret;
end;
$$;

alter function private.get_secret (secret_name text) OWNER to "postgres";

-- Calls the `resend` edge function, presenting one of the project's SECRET keys. It must
-- NOT use the publishable/anon key: that key is public (it ships in the browser bundle),
-- so authenticating with it would leave `resend` — which takes its recipient and template
-- arguments from the request — callable by anyone as an open relay for branded mail. The
-- function authorizes by comparing the presented key against the project's secret keys
-- (supabase/functions/_shared/auth.ts), which works for both a legacy `service_role` JWT
-- and a newer opaque `sb_secret_...` key. Hosted projects must have the `secret_key` and
-- `supabase_url` vault secrets set by hand; local dev seeds them from [db.vault] in
-- supabase/config.toml.
create or replace function public.send_email () RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
set
	"search_path" to '' as $$
declare
  -- btrim so a secret pasted with a stray newline or space still works.
  _key text := btrim(coalesce(private.get_secret('secret_key'), private.get_secret('service_role_key'), ''));
  _url text := btrim(coalesce(private.get_secret('supabase_url'), ''));
begin
  -- Delivery is BEST EFFORT. The row in public.emails is the durable record that a message
  -- was meant to go out; whether the edge function can be reached is a deployment concern
  -- and must never roll back the caller's transaction. Before this, a missing or malformed
  -- supabase_url raised here and failed whatever action had queued the mail — volunteering,
  -- proposing a venue, verifying an email — on a project whose only fault was a bad secret.
  if _key = '' or _url = '' then
    raise warning 'send_email: % is not configured, so email % was recorded but not delivered',
      case when _url = '' then 'the supabase_url vault secret' else 'the secret_key vault secret' end,
      new.id;
    return new;
  end if;
  begin
    -- Post to the Resend edge function. If the supabase URL is set to localhost, replace it with host.docker.internal so we hit the host machine, not the container.
    -- The key goes on `apikey`: `Authorization: Bearer` is reserved for JWTs, and the newer
    -- opaque `sb_secret_...` keys are rejected there.
    perform net.http_post(
      url:=replace(_url, '127.0.0.1', 'host.docker.internal') || '/functions/v1/resend',
      headers:=jsonb_build_object(
          'Content-Type', 'application/json',
          'apikey', _key
      )::jsonb,
      body:=jsonb_build_object(
        'to', new.email,
        'subject', new.subject,
        'message', new.message,
        'event', new.event,
        'args', new.args
      )
    );
  exception when others then
    -- pg_net validates the URL synchronously, so a malformed value raises here rather than
    -- in the background worker. Warn and carry on.
    raise warning 'send_email: email % was recorded but could not be queued for delivery: % (%)',
      new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$$;

alter function public.send_email () OWNER to "postgres";

grant all on FUNCTION public.send_email () to "anon";

grant all on FUNCTION public.send_email () to "authenticated";

grant all on FUNCTION public.send_email () to "service_role";

--------------------------------------
-- Triggers
--
create or replace trigger send_on_email_insert
after INSERT on public.emails for EACH row
execute FUNCTION public.send_email ();
