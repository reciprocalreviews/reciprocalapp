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
-- supabase/config.toml. There is no fallback to the older `service_role_key` secret name:
-- that transition finished, and the retired secret was dropped in 20260802000000.
create or replace function public.send_email () returns trigger language plpgsql security definer
set
	"search_path" to '' as $$
declare
  -- btrim so a secret pasted with a stray newline or space still works.
  _key text := btrim(coalesce(private.get_secret('secret_key'), ''));
  _url text := btrim(coalesce(private.get_secret('supabase_url'), ''));
begin
  -- Delivery is BEST EFFORT. The row in public.emails is the durable record that a message
  -- was meant to go out; whether the edge function can be reached is a deployment concern
  -- and must never roll back the caller's transaction.
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
after insert on public.emails for each row
execute function public.send_email ();

--------------------------------------
-- RPC (authoritative definition from migration 20260719030000_queue_email_rpc)
create or replace function public.queue_email (
	_event text,
	_args text[] default '{}',
	_scholars uuid[] default null,
	_proposal uuid default null
) returns jsonb language plpgsql security definer
set
	"search_path" to 'public',
	'pg_temp' as $$
declare
	_caller uuid := (select auth.uid());
	_recipients jsonb := '[]'::jsonb;
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	if _event is null or _event = '' then
		raise exception 'An event is required';
	end if;
	-- VerifyEmail is the one template that renders an ARGUMENT as a clickable link
	-- (templates.ts `urlArgs`), so allowing it here would let a caller send branded mail
	-- containing a link of their choosing. It is queued only by
	-- public.request_email_verification, which builds the URL itself.
	if _event = 'VerifyEmail' then
		raise exception 'VerifyEmail is queued only by request_email_verification';
	end if;

	-- Resolve scholar recipients. Scholars with no verified contact email are skipped:
	-- scholars.email holds only verified addresses, so a null here means "not verified".
	if _scholars is not null then
		insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
		select _event, s.id, _caller, null, s.email, null, null, to_jsonb(_args)
		from public.scholars s
		where s.id = any(_scholars) and s.email is not null;

		select coalesce(jsonb_agg(jsonb_build_object('name', s.name, 'email', s.email)), '[]'::jsonb)
		into _recipients
		from public.scholars s
		where s.id = any(_scholars) and s.email is not null;
	end if;

	-- Resolve a proposal's editor addresses.
	if _proposal is not null then
		insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
		select _event, null, _caller, null, e, null, null, to_jsonb(_args)
		from public.proposals p, unnest(p.editors) as e
		where p.id = _proposal and e is not null and e <> '';

		select _recipients || coalesce(jsonb_agg(jsonb_build_object('name', e, 'email', e)), '[]'::jsonb)
		into _recipients
		from public.proposals p, unnest(p.editors) as e
		where p.id = _proposal and e is not null and e <> '';
	end if;

	return _recipients;
end;
$$;

alter function public.queue_email (text, text[], uuid[], uuid) OWNER to "postgres";

revoke
execute on function public.queue_email (text, text[], uuid[], uuid)
from
	public,
	anon;

grant
execute on function public.queue_email (text, text[], uuid[], uuid) to authenticated;

--------------------------------------
-- The alias, defined once.
--
-- Hardcoded rather than configured: it is a property of the deployment's DNS, changes
-- about never, and a settings table would make a silent misconfiguration possible in the
-- one path that reports that other paths are broken. Mirrored in
-- supabase/functions/_shared/emailShell.ts as SUPPORT_EMAIL — keep the two in sync.
create or replace function public.steward_inbox () returns text language sql immutable
set
	"search_path" to '' as $$
	select 'stewards@reciprocal.reviews'::text;
$$;

alter function public.steward_inbox () OWNER to "postgres";

grant
execute on function public.steward_inbox () to authenticated;

--------------------------------------
-- queue_steward_email: queue a steward notification to the shared inbox.
--
-- Deliberately a separate function from queue_email rather than another branch inside it.
-- queue_email's security rests on never accepting a recipient: it resolves scholars by id
-- or reads a proposal's editors. This function accepts no recipient either — the address
-- is fixed — but it does bypass the "recipient must be a scholar with a verified email"
-- rule, so the safety has to come from somewhere else. It comes from the event whitelist:
-- without it, any authenticated user could render ANY template into the stewards' inbox,
-- which is precisely the mailbox least able to ignore what arrives.
--
-- The residual exposure is bounded and deliberate: an authenticated user can queue a
-- steward notification with argument values of their choosing. That is the same shape as
-- queue_email's residual (no prose, no links, attributable via emails.sender), and the
-- inbox is staffed by the people best placed to recognize junk.
create or replace function public.queue_steward_email (_event text, _args text[] default '{}') returns void language plpgsql security definer
set
	"search_path" to 'public',
	'pg_temp' as $$
declare
	_caller uuid := (select auth.uid());
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	-- Whitelist, not a blacklist: a template added later is un-sendable here until
	-- someone deliberately adds it, which is the failure direction we want.
	if _event is null or _event not in ('ProposalCreatedStewards', 'ReconciliationFailed') then
		raise exception 'Not a steward notification: %', coalesce(_event, 'null');
	end if;

	insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
	values (_event, null, _caller, null, public.steward_inbox(), null, null, to_jsonb(_args));
end;
$$;

alter function public.queue_steward_email (text, text[]) OWNER to "postgres";

revoke
execute on function public.queue_steward_email (text, text[])
from
	public,
	anon;

grant
execute on function public.queue_steward_email (text, text[]) to authenticated;
