-- Thank-you and proposal-decline emails are rendered at send time, like every other email.
--
-- queue_thanks_emails and decline_venue_proposal used to accept a subject and message rendered
-- by the caller. The resend function sends a row's own subject and message as they are, and the
-- branded shell passes inline markup through, so an author calling queue_thanks_emails directly
-- could send a venue's editors (and, with vetting off, its reviewers) mail with any subject,
-- body and links under the platform's name. Both now take ids only, read the values each email
-- shows from their own rows, and leave subject and message null so the registry renders them,
-- escaped, when the email is sent.

drop function if exists public.queue_thanks_emails (uuid, text, text, text);

drop function if exists public.decline_venue_proposal (uuid, text, text);

create or replace function public.queue_thanks_emails (_thanks_id uuid, _audience text) returns integer language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_t public.thanks;
	_vet boolean;
	_count integer;
	_path text;
begin
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	select * into _t from public.thanks where id = _thanks_id;
	if not found then
		raise exception 'Thank-you note not found';
	end if;
	select vet_thanks, coalesce(slug, id::text) into _vet, _path from public.venues where id = _t.venue;

	if _audience = 'recipients' then
		if _t.status <> 'approved' then
			raise exception 'Only an approved note can be delivered';
		end if;
		if not (
			public.isAdmin(_t.venue)
			or public.isPriorityZero(_t.venue)
			or (not _vet and _caller = _t.author)
		) then
			raise exception 'You are not authorized to deliver this note';
		end if;
		insert into public.emails (event, scholar, sender, venue, email, args)
		select 'ThanksReceived', s.id, null, _t.venue, s.email,
			jsonb_build_array(_t.message, _path, _t.submission::text)
		from (
			select distinct a.scholar
			from public.assignments a
			where a.submission = _t.submission and a.approved = true and a.scholar <> _t.author
		) r
		join public.scholars s on s.id = r.scholar
		where s.email is not null and public.notification_allowed(s.id, 'ThanksReceived');

	elsif _audience = 'vetters' then
		if _caller <> _t.author then
			raise exception 'You are not authorized to notify vetters';
		end if;
		insert into public.emails (event, scholar, sender, venue, email, args)
		select 'ThanksPendingReview', s.id, null, _t.venue, s.email,
			jsonb_build_array(_path, _t.submission::text)
		from (
			select unnest(admins) as scholar from public.venues where id = _t.venue
			union
			select v.scholarid
			from public.volunteers v
			join public.roles r on r.id = v.roleid
			where r.venueid = _t.venue and r.priority = 0 and v.accepted = 'accepted'
		) vt
		join public.scholars s on s.id = vt.scholar
		where s.email is not null and s.id <> _caller
			and public.notification_allowed(s.id, 'ThanksPendingReview');

	-- The author's copy of the GOOD outcome. A separate audience rather than a parameter for
	-- the event, because the event being fixed per audience is what keeps this function from
	-- becoming a way to send any template to anyone: the caller picks an audience from a closed
	-- set, and the function decides both who is written to and what it says it is.
	elsif _audience = 'author_shared' then
		if not (public.isAdmin(_t.venue) or public.isPriorityZero(_t.venue)) then
			raise exception 'You are not authorized to notify the author';
		end if;
		insert into public.emails (event, scholar, sender, venue, email, args)
		select 'ThanksShared', s.id, null, _t.venue, s.email,
			jsonb_build_array(_path, _t.submission::text)
		from public.scholars s
		where s.id = _t.author and s.email is not null
			and public.notification_allowed(s.id, 'ThanksShared');

	elsif _audience = 'author' then
		if not (public.isAdmin(_t.venue) or public.isPriorityZero(_t.venue)) then
			raise exception 'You are not authorized to notify the author';
		end if;
		insert into public.emails (event, scholar, sender, venue, email, args)
		select 'ThanksDeclined', s.id, null, _t.venue, s.email,
			jsonb_build_array(coalesce(_t.decline_reason, ''), _path, _t.submission::text)
		from public.scholars s
		where s.id = _t.author and s.email is not null
			and public.notification_allowed(s.id, 'ThanksDeclined');

	else
		raise exception 'Unknown thanks email audience';
	end if;

	get diagnostics _count = row_count;
	return _count;
end;
$function$;

revoke
execute on function public.queue_thanks_emails (uuid, text)
from
	public,
	anon;

grant
execute on function public.queue_thanks_emails (uuid, text) to authenticated;

create or replace function public.decline_venue_proposal (_proposal_id uuid) returns integer language plpgsql security definer
set
	"search_path" to 'public',
	'pg_temp' as $function$
declare
	_caller uuid := (select auth.uid());
	_proposal public.proposals;
	_supporters integer;
	_editors integer;
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	if not public.isSteward() then
		raise exception 'Only stewards can decline venue proposals';
	end if;

	select * into _proposal from public.proposals where id = _proposal_id;
	if not found then
		raise exception 'Proposal not found';
	end if;

	-- The supporters, who are scholars and so have a preference to honour.
	insert into public.emails (event, scholar, sender, venue, email, args)
	select 'ProposalDeclined', s.id, _caller, null, s.email, jsonb_build_array(_proposal.title)
	from public.supporters p
	join public.scholars s on s.id = p.scholarid
	where p.proposalid = _proposal_id
		and s.email is not null
		and public.notification_allowed(s.id, 'ProposalDeclined');

	get diagnostics _supporters = row_count;

	-- The listed editors, who are addresses rather than accounts. No preference applies:
	-- there is no scholar to hold one, which is the same reason ProposalCreatedEditors is
	-- sent to them unconditionally. Anyone listed who also supported is skipped, so a person
	-- who is both does not get two copies.
	insert into public.emails (event, scholar, sender, venue, email, args)
	select 'ProposalDeclined', null, _caller, null, e, jsonb_build_array(_proposal.title)
	from unnest(_proposal.editors) as e
	where e is not null
		and e <> ''
		and e not in (
			select s.email from public.supporters p
			join public.scholars s on s.id = p.scholarid
			where p.proposalid = _proposal_id and s.email is not null
		);

	-- Two counters rather than one: GET DIAGNOSTICS assigns an item to a variable and takes
	-- no expression, so `_count = _count + row_count` is a syntax error rather than a sum.
	get diagnostics _editors = row_count;

	delete from public.proposals where id = _proposal_id;

	return _supporters + _editors;
end;
$function$;

alter function public.decline_venue_proposal (uuid) OWNER to "postgres";

-- Explicitly revoked, not merely un-granted: Supabase's ALTER DEFAULT PRIVILEGES hands anon
-- EXECUTE on every function created in `public` at creation time.
revoke
execute on function public.decline_venue_proposal (uuid)
from
	public,
	anon;

grant
execute on function public.decline_venue_proposal (uuid) to authenticated;
