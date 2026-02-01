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
	-- The optional venue for which the email was sent
	venue uuid,
	-- When the email was sent
	time_sent timestamp with time zone default now() not null,
	-- The email to whom the email was sent
	email text not null,
	-- The subject of the email
	subject text not null,
	-- The body of the email
	message text not null
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

create policy "recipients and venue admins can see the emails sent" on public.emails for
select
	to authenticated,
	anon using (
		(
			(
				(
					select
						auth.uid () as uid
				)=scholar
			)
			or (
				(venue is not null)
				and public.isAdmin (venue)
			)
		)
	);

create policy "authenticated scholars can send email" on public.emails for INSERT to authenticated
with
	check (true);

create policy "emails can't be edited" on public.emails
for update
	to authenticated,
	anon using (false);

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

create or replace function public.send_email () RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
set
	"search_path" to '' as $$
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
