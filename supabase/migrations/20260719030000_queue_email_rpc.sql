-- Close the branded-email relay: revoke direct INSERT on public.emails and route every
-- send through a SECURITY DEFINER RPC that resolves recipients server-side.
--
-- The "authenticated scholars can send email" policy was `with check (true)`, and an
-- AFTER INSERT trigger posts each row to the `resend` edge function. Any authenticated
-- user could therefore insert a row naming ANY recipient with ANY subject and body, and it
-- went out branded from notifications@reciprocal.reviews. Self-service ORCID sign-up (#19)
-- makes "authenticated" a low bar, so this is an open relay for phishing.
--
-- Two properties close it, and both are needed:
--
--   1. RECIPIENTS are resolved here from scholar ids (or a proposal's editor list), never
--      accepted as free-text addresses. Mail can only reach a scholar who exists and has a
--      VERIFIED contact email (scholars.email is null until verify_email commits it, #27),
--      so this is also what keeps unverified addresses un-notified.
--   2. CONTENT is not accepted at all. Rows carry an event plus arguments and are rendered
--      at send time from the shared template registry
--      (supabase/functions/_shared/templates.ts, see 20260719020000). A caller can choose
--      which template and its argument values, but cannot author prose — and argument
--      values have their URL schemes defanged at render time, so they cannot become
--      clickable links.
--
-- Residual, deliberately deferred: this function does not yet check that the caller has a
-- *relationship* to each recipient, so a scholar can send a real template to a scholar they
-- have no business emailing. That is bounded (no arbitrary prose, no external addresses, no
-- links) and attributable via emails.sender. Per-event authorization is a follow-up.

--------------------------------------
-- Revoke the ability to insert directly.
drop policy if exists "authenticated scholars can send email" on public.emails;

revoke insert on table public.emails
from
	authenticated,
	anon;

--------------------------------------
-- queue_email: resolve recipients and queue rendered-at-send-time email.
--
-- `_scholars` addresses scholars by id. `_proposal` covers ProposalCreatedEditors, whose
-- recipients are the proposal's editor addresses — those are not scholars and so cannot be
-- resolved by id. They remain caller-influenced (the caller wrote them onto the proposal),
-- but they are now persisted, attributable, and steward-reviewable rather than an invisible
-- one-shot send.
--
-- Returns the recipients actually queued, so the client can show "emailed X" notifications.
create or replace function public.queue_email (
	_event text,
	_args text[] default '{}',
	_scholars uuid[] default null,
	_proposal uuid default null
) returns jsonb language plpgsql security definer
set
	"search_path" to 'public', 'pg_temp' as $$
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

revoke execute on function public.queue_email (text, text[], uuid[], uuid)
from
	public,
	anon;

grant execute on function public.queue_email (text, text[], uuid[], uuid) to authenticated;
