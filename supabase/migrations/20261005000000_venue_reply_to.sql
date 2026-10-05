-- Mail about a venue answers to the venue.
--
-- Every notification about a venue used to carry Reply-To: stewards@ and a footer saying a
-- steward would read the reply, so people wrote to the platform's stewards with questions
-- about a journal or conference that only its editors could answer. This migration:
--
--   1. adds venue_reply_to() and a BEFORE INSERT trigger that gives a row with a `venue`
--      and no `reply_to` the venue's first admin with a verified address;
--   2. adds an optional `_venue` to queue_email and queue_reminder_email, so the
--      application and the reminder cron can say which venue a message is about;
--   3. has send_email() pass the venue's title and path to the `resend` function, which
--      names the venue in the footer.

--------------------------------------
-- venue_reply_to: where a reply to mail about a venue should go.
--
-- The venue's first administrator with a verified contact address, or null when none has
-- one. Mail about a venue used to reply to stewards@ like everything else, and its footer
-- said a steward would read the reply, so people wrote to the platform's stewards with
-- questions about a journal's reviewing that only its editors could answer. One address
-- because reply_to holds one, and the first because it is the longest-standing, the rule
-- _notify_new_volunteer uses for whom it addresses. The footer links the venue's page,
-- which lists the rest.
--
-- Security invoker: it reads venues.admins and scholars.email, both world-readable, and
-- its only caller below already runs as the table owner.
create or replace function public.venue_reply_to (_venue uuid) returns text language sql stable
set
	"search_path" to '' as $$
	select s.email
	from public.venues v
	cross join lateral unnest(v.admins) with ordinality as a (scholar, position)
	join public.scholars s on s.id = a.scholar
	where v.id = _venue and s.email is not null
	order by a.position
	limit 1;
$$;

alter function public.venue_reply_to (uuid) OWNER to "postgres";

-- resolve_venue_reply_to: give a row about a venue that venue's reply address.
--
-- A trigger rather than a line in each producer, because the producers are many --
-- queue_email, queue_reminder_email, queue_thanks_emails, create_volunteer -- and the rule
-- is one: mail about a venue answers to the venue. A producer added later inherits it by
-- setting `venue`. A row that already names a reply_to keeps it (a call for bids replies to
-- the editor who wrote it).
--
-- NewVolunteer is the exception. Its reply path is the new volunteer, so that answering it
-- is the welcome; one with no verified address has no reply path, and the notice goes to
-- the venue's editors, who would only be replying to themselves.
create or replace function public.resolve_venue_reply_to () returns trigger language plpgsql
set
	"search_path" to '' as $$
begin
	if new.venue is not null and new.reply_to is null and new.event is distinct from 'NewVolunteer' then
		new.reply_to := public.venue_reply_to(new.venue);
	end if;
	return new;
end;
$$;

alter function public.resolve_venue_reply_to () OWNER to "postgres";

create or replace trigger resolve_venue_reply_to_on_email_insert
before insert on public.emails for each row
execute function public.resolve_venue_reply_to ();

--------------------------------------
-- send_email: unchanged apart from venue_title and venue_path in the payload.
create or replace function public.send_email () returns trigger language plpgsql security definer
set
	"search_path" to '' as $$
declare
  -- btrim so a secret pasted with a stray newline or space still works.
  _key text := btrim(coalesce(private.get_secret('secret_key'), ''));
  _url text := btrim(coalesce(private.get_secret('supabase_url'), ''));
  -- The application origin the rendered links should point at. Falls back to
  -- production, so an unconfigured project behaves as it did before.
  _origin text := public.site_origin();
  -- pg_net's handle on the request. Kept, where it used to be discarded: it is the only
  -- way to find the answer, which arrives asynchronously in net._http_response.
  _request_id bigint;
begin
  -- Delivery is still BEST EFFORT. The row in public.emails is the durable record that a
  -- message was meant to go out; whether the edge function can be reached is a deployment
  -- concern and must never roll back the caller's transaction. What changes here is that
  -- "best effort" stops meaning "unrecorded": both failure paths below now write a
  -- terminal delivery state, so the row says what happened instead of only leaving a
  -- warning in a log nobody reads.
  --
  -- The state is recorded with an UPDATE against the row we were just handed, not by
  -- assigning to NEW: this is an AFTER trigger, so the row is already written and NEW is a
  -- copy. That UPDATE is allowed despite the "emails can't be edited" policy (using(false))
  -- because this function is SECURITY DEFINER owned by postgres, which owns the table, and
  -- the table does not FORCE row level security -- so policies do not apply to it. The
  -- policy still binds `authenticated`, which is who it was written for.
  --
  -- AFTER rather than BEFORE, deliberately. A BEFORE INSERT trigger runs before the table's
  -- CHECK constraints and foreign keys (emails_cc_shape, emails_scholar_fkey, ...), so
  -- moving this earlier to make NEW writable would post the message to Resend and only then
  -- discover that the row it was sending is about to be rejected: mail sent on behalf of a
  -- row that never existed. One extra UPDATE is the cheaper half of that trade.
  if _key = '' or _url = '' then
    raise warning 'send_email: % is not configured, so email % was recorded but not delivered',
      case when _url = '' then 'the supabase_url vault secret' else 'the secret_key vault secret' end,
      new.id;
    update public.emails
    set delivery = 'failed',
        delivery_detail = 'not posted: the '
          || case when _url = '' then 'supabase_url' else 'secret_key' end
          || ' vault secret is not configured',
        delivery_at = now()
    where id = new.id;
    return new;
  end if;
  begin
    -- Post to the Resend edge function. If the supabase URL is set to localhost, replace it with host.docker.internal so we hit the host machine, not the container.
    -- The key goes on `apikey`: `Authorization: Bearer` is reserved for JWTs, and the newer
    -- opaque `sb_secret_...` keys are rejected there.
    select net.http_post(
      url:=replace(_url, '127.0.0.1', 'host.docker.internal') || '/functions/v1/resend',
      headers:=jsonb_build_object(
          'Content-Type', 'application/json',
          'apikey', _key
      )::jsonb,
      body:=jsonb_build_object(
        'to', new.email,
        -- to_jsonb of a null array yields JSON null, which the edge function's `.nullish()`
        -- schema accepts, so a message with no Cc is indistinguishable from one sent before
        -- the column existed.
        'cc', to_jsonb(new.cc),
        -- Null means "the stewards", which the edge function substitutes. Only SECURITY
        -- DEFINER functions can set it -- the table's INSERT privilege is revoked from
        -- authenticated and anon -- which is the same property that keeps `to` safe.
        'reply_to', new.reply_to,
        'subject', new.subject,
        'message', new.message,
        'event', new.event,
        'args', new.args,
        'origin', _origin,
        -- Who the message is to, so an optional notice's footer can link to the recipient's
        -- own notification settings (settingsUrlFor in _shared/templates.ts). Null for mail
        -- with no scholar, such as the steward inbox, which then gets no such link.
        'scholar', new.scholar,
        -- The venue the message is about, so the footer can name it and send questions about
        -- it to its editors rather than the stewards. Its short name where it has one, as the
        -- venue bar shows it (venueBarName). Both null for mail that is not about a venue,
        -- which keeps the steward footer.
        'venue_title', (select coalesce(nullif(btrim(v.short_title), ''), v.title) from public.venues v where v.id = new.venue),
        'venue_path', (select coalesce(v.slug, v.id::text) from public.venues v where v.id = new.venue)
      )
    ) into _request_id;

    -- 'queued' is an honest non-answer, not a success. net.http_post returns the instant it
    -- has written a row to net.http_request_queue; nothing has been delivered yet and
    -- nothing may ever be. public.reconcile_email_delivery() turns this into a verdict.
    update public.emails
    set request_id = _request_id,
        delivery = 'queued',
        delivery_at = now()
    where id = new.id;
  exception when others then
    -- pg_net validates the URL synchronously, so a malformed value raises here rather than
    -- in the background worker. Warn, record it as terminal, and carry on.
    raise warning 'send_email: email % was recorded but could not be queued for delivery: % (%)',
      new.id, sqlerrm, sqlstate;
    update public.emails
    set delivery = 'failed',
        delivery_detail = 'not posted: ' || sqlerrm || ' (' || sqlstate || ')',
        delivery_at = now()
    where id = new.id;
  end;
  return new;
end;
$$;

alter function public.send_email () OWNER to "postgres";

-- Nobody but the owner. This runs from the send_on_email_insert trigger and is never called
-- directly, and it is SECURITY DEFINER over the mail log, so an EXECUTE grant to anon or
-- authenticated is pure surface. 20260831000000 revoked exactly this (its `_triggers` list);
-- the grants that used to stand here were left over from before that migration, and any
-- `create or replace` of this function re-opens the hole unless the revoke travels with it —
-- Supabase's default privileges re-grant EXECUTE to anon and authenticated at creation time.
-- supabase/tests/rls/definer_grants.sql check 1 is what catches it.
revoke
execute on function public.send_email ()
from
	public,
	anon,
	authenticated;

--------------------------------------
-- queue_email gains `_venue`. Dropped first: a new trailing parameter makes a new
-- overload, and leaving the old one would keep a second, venue-blind entry point.
drop function if exists public.queue_email (text, text[], uuid[], uuid);

create or replace function public.queue_email (
	_event text,
	_args text[] default '{}',
	_scholars uuid[] default null,
	_proposal uuid default null,
	_venue uuid default null
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
	--
	-- Silenced scholars are skipped too. This is the whole of the opt-out mechanism: the
	-- registry used to say each producer was responsible for consulting
	-- public.notification_settings itself, and exactly one of them ever did, which is why the
	-- profile could only ever offer one checkbox. Resolving it here means marking a template
	-- `optional` is genuinely all it takes.
	--
	-- A template with no public.optional_emails row is consequential, matches nothing here,
	-- and always sends -- so a template missing from the seed fails toward delivering mail.
	if _scholars is not null then
		insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
		select _event, s.id, _caller, _venue, s.email, null, null, to_jsonb(_args)
		from public.scholars s
		where s.id = any(_scholars) and s.email is not null
			and public.notification_allowed(s.id, _event);

		-- The same predicate, because this is what the caller is told it sent. Reporting the
		-- unfiltered list would have the application announce "emailed 4 people" for a notice
		-- that reached one, and those counts surface to users as feedback banners.
		select coalesce(jsonb_agg(jsonb_build_object('name', s.name, 'email', s.email)), '[]'::jsonb)
		into _recipients
		from public.scholars s
		where s.id = any(_scholars) and s.email is not null
			and public.notification_allowed(s.id, _event);
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

alter function public.queue_email (text, text[], uuid[], uuid, uuid) OWNER to "postgres";

revoke
execute on function public.queue_email (text, text[], uuid[], uuid, uuid)
from
	public,
	anon;

grant
execute on function public.queue_email (text, text[], uuid[], uuid, uuid) to authenticated;

--------------------------------------
-- queue_reminder_email gains `_venue`, for the same reason.
drop function if exists public.queue_reminder_email (text, text[], uuid);

create or replace function public.queue_reminder_email (
	_event text,
	_args text[],
	_scholar uuid,
	_venue uuid default null
) returns integer language plpgsql security definer
set
	"search_path" to 'public',
	'pg_temp' as $$
declare
	_count integer;
begin
	if _event is null or _event = '' then
		raise exception 'An event is required';
	end if;
	-- The same refusal queue_email makes, for the same reason: VerifyEmail renders an
	-- argument as a clickable link, so it is queued only by request_email_verification.
	if _event = 'VerifyEmail' then
		raise exception 'VerifyEmail is queued only by request_email_verification';
	end if;

	insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
	select _event, s.id, null, _venue, s.email, null, null, to_jsonb(_args)
	from public.scholars s
	where s.id = _scholar
		and s.email is not null
		and public.notification_allowed(s.id, _event);

	get diagnostics _count = row_count;
	return _count;
end;
$$;

alter function public.queue_reminder_email (text, text[], uuid, uuid) OWNER to "postgres";

-- Explicitly revoked, not merely un-granted: Supabase's ALTER DEFAULT PRIVILEGES hands anon
-- and authenticated EXECUTE on every function created in `public` at creation time, and
-- `revoke ... from public` does not take those back. See 20260831000000. Leaving this open
-- would hand any signed-in user a way to send branded mail to any scholar, with no caller
-- recorded against it -- strictly worse than queue_email, which at least stamps `sender`.
revoke
execute on function public.queue_reminder_email (text, text[], uuid, uuid)
from
	public,
	anon,
	authenticated;

grant
execute on function public.queue_reminder_email (text, text[], uuid, uuid) to service_role;
