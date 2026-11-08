-- Bring three function bodies into line with the schema files that document them.
--
-- WHY
--
-- Comment-only. Nothing here changes what any of these functions does.
--
-- 20260829000000 (`new_volunteer_notice`) reissued `send_email`, `export_scholar_data`, and
-- `forget_scholar`, and the same commit rewrote their comments in supabase/schemas/ — but
-- the two wordings ended up different. A function's comments live in `prosrc`, so that is a
-- real difference between what the database holds and what supabase/schemas/ says it holds,
-- and ARCHITECTURE.md calls supabase/schemas/ authoritative. CI's drift check compares the
-- two and had nothing to say about it until now; the check is what surfaced it, on an
-- unrelated push.
--
-- Reconciled toward the schema files rather than away from them, because their wording is
-- the better of the two — `export_scholar_data`'s explains what the `cc` branch is for and
-- what went wrong without it, and `forget_scholar`'s says why an address has to be captured
-- before the row is scrubbed. Editing 20260829000000 in place would have been the smaller
-- diff and the wrong move: it has already run on staging and production, so those databases
-- would have kept the old text while the file claimed otherwise — the same drift, now
-- invisible to the check that just caught it.
--
-- `create or replace function` keeps existing privileges and leaves the `send_email` trigger
-- attached, so no grant or trigger has to be restated here.


--------------------------------------
-- send_email — verbatim from supabase/schemas/emails.sql
--------------------------------------
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
        'origin', _origin
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


--------------------------------------
-- export_scholar_data — verbatim from supabase/schemas/erasures.sql
--------------------------------------
create or replace function public.export_scholar_data (_scholar uuid default null) returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_caller uuid := (select auth.uid());
	_target uuid := coalesce(_scholar, _caller);
	_target_email text;
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	if _target <> _caller and not public.isSteward() then
		raise exception 'You can only export your own data' using errcode = 'RR006';
	end if;

	-- Resolved once rather than per row: emails.cc holds addresses, not ids.
	select email into _target_email from public.scholars s where s.id = _target;

	return jsonb_build_object(
		'exported_at', now(),
		'scholar', (select to_jsonb(s) from public.scholars s where s.id = _target),
		'volunteering', (select coalesce(jsonb_agg(to_jsonb(v)), '[]'::jsonb) from public.volunteers v where v.scholarid = _target),
		'submissions', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.submissions x where _target = any (x.authors)),
		'assignments', (select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) from public.assignments a where a.scholar = _target),
		'conflicts', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from public.conflicts c where c.scholarid = _target),
		'supported_proposals', (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from public.supporters p where p.scholarid = _target),
		'thanks_written', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.thanks t where t.author = _target),
		'transactions', (select coalesce(jsonb_agg(to_jsonb(t) order by t.seq), '[]'::jsonb) from public.transactions t
			where t.creator = _target or t.from_scholar = _target or t.to_scholar = _target),
		'tokens_held', (select coalesce(jsonb_object_agg(currency, n), '{}'::jsonb)
			from (select currency, count(*) as n from public.tokens where scholar = _target group by currency) c),
		-- The ledger makes this possible for the first time: before token_events
		-- there was no record of where a scholar's tokens had been.
		'token_history', (select coalesce(jsonb_agg(to_jsonb(e) order by e.seq), '[]'::jsonb)
			from public.token_events e where e.scholar = _target or e.prev_scholar = _target),
		-- Addressed to them, or copied on it. `m.scholar` names only the To recipient, so
		-- before the cc branch a scholar's own export said nothing about notices they
		-- actually received. SECURITY DEFINER, so this scan is not limited by the emails
		-- SELECT policy — which is what lets it report mail the scholar received but cannot
		-- read the row for. Still only the event and the time: the export says what
		-- arrived, not what it said.
		'emails_received', (select coalesce(jsonb_agg(jsonb_build_object('event', m.event, 'time_sent', m.time_sent)), '[]'::jsonb)
			from public.emails m
			where m.scholar = _target
				or (_target_email is not null and m.cc is not null and _target_email = any (m.cc))),
		-- Which notices they have silenced. Small, but it is a preference they set, and so
		-- part of what the platform holds about them.
		'notification_settings', (select coalesce(jsonb_agg(to_jsonb(n)), '[]'::jsonb)
			from public.notification_settings n where n.scholar = _target)
	);
end;
$$;


--------------------------------------
-- forget_scholar — verbatim from supabase/schemas/erasures.sql
--------------------------------------
create or replace function public.forget_scholar (_scholar uuid) returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_placeholder text := 'erased-' || _scholar || '@invalid';
	_emails int;
	_copied int;
	_audit int;
	_old_email text;
begin
	if _scholar is null then
		raise exception 'forget_scholar requires a scholar id';
	end if;

	-- Captured BEFORE the scholars row below is scrubbed. Mail where this scholar was
	-- merely copied, or was the person replies went to, is reachable only by address:
	-- emails.cc and emails.reply_to hold addresses, and neither is matched by the
	-- scholar/sender scrub further down.
	select email into _old_email from public.scholars where id = _scholar;

	-- The identity behind the account. The row stays so the foreign keys hold, but
	-- nothing in it points at a person any more, and the credentials are destroyed
	-- so the account cannot be used again.
	update auth.users
	set
		email = _placeholder,
		phone = null,
		encrypted_password = null,
		raw_user_meta_data = '{}'::jsonb,
		raw_app_meta_data = '{}'::jsonb,
		confirmation_token = '',
		recovery_token = '',
		email_change = ''
	where id = _scholar;

	-- ORCID is the login identity; `status` is free text the scholar wrote about
	-- themselves and can name anyone.
	update public.scholars
	set
		name = null,
		email = null,
		orcid = null,
		-- Erasure destroys the identity, so it must destroy the privilege with it. A
		-- tombstone that is still a steward appears on the public /about list as
		-- "anonymous", still satisfies isSteward(), and would satisfy set_steward's
		-- last-steward guard on behalf of a uuid nobody can sign into — letting the
		-- last real steward be demoted while nobody is left who can act.
		steward = false,
		-- Emptied rather than nulled: `status` is NOT NULL. It is free text the
		-- scholar wrote about themselves and can name anyone, so it has to go.
		status = '',
		available = false
	where id = _scholar;

	-- A pending verification holds an address that was never even confirmed.
	delete from public.email_verifications where scholar = _scholar;

	-- Queued and sent mail carries the address and, in `args`, rendered values that
	-- can include their name. The row stays as evidence that a message was sent;
	-- its contents do not.
	update public.emails
	set
		email = _placeholder,
		subject = null,
		message = null,
		args = '[]'::jsonb,
		-- Mail addressed TO this scholar may also have copied others and named a third
		-- party as its reply address. Neither belongs to the erased scholar, but both are
		-- contents of a message whose contents are being destroyed.
		cc = null,
		reply_to = null
	where scholar = _scholar or sender = _scholar;
	get diagnostics _emails = row_count;

	-- Mail about SOMEBODY ELSE that merely copied this scholar, or that replied to them.
	-- The rest of the row belongs to other people and stays; only this scholar's address
	-- leaves it. Without this pass an erased address survived indefinitely in notices about
	-- other scholars — the exact thing erasure exists to prevent.
	if _old_email is not null then
		update public.emails
		set
			cc = nullif(array_remove(cc, _old_email), '{}'::text[]),
			reply_to = case when reply_to = _old_email then null else reply_to end
		where (cc is not null and _old_email = any (cc))
			or reply_to = _old_email;
		get diagnostics _copied = row_count;
	else
		_copied := 0;
	end if;

	-- audit_log keeps WHOLE rows, so every edit this scholar's profile ever
	-- received contains their name and address. Scrub the payloads and the actor,
	-- leaving which table changed and when — the append-only guard permits exactly
	-- this much and nothing more.
	perform set_config('app.erasure', 'on', true);

	update public.audit_log
	set
		before = case when before is not null then '{}'::jsonb end,
		after = case when after is not null then '{}'::jsonb end
	where tbl = 'scholars' and row_id = _scholar;
	get diagnostics _audit = row_count;

	update public.audit_log set actor = null where actor = _scholar;

	-- token_events.actor is the only field here that names a person; the ownership
	-- columns are left untouched, because the ledger is reconstructed from them.
	update public.token_events set actor = null where actor = _scholar;

	perform set_config('app.erasure', '', true);

	insert into public.erasures (subject, completed_at)
	values (_scholar, now())
	on conflict (subject) do update set completed_at = now();

	return jsonb_build_object(
		'scholar', _scholar,
		'emails_scrubbed', _emails,
		-- Reported separately from emails_scrubbed: these rows were not scrubbed, only
		-- de-addressed, and the receipt should not imply that mail about other people was
		-- emptied out.
		'emails_uncopied', _copied,
		'audit_payloads_scrubbed', _audit
	);
end;
$$;
