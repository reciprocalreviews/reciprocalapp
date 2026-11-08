-- Inactive venues take no new work (#42).
--
-- An inactive venue -- one being configured, or one that has closed -- was kept out of only
-- by the interface: everyone but its admins reaches a page with the admins' message. Nothing
-- in the database said so, and its admins could still start anything. Now no one can create
-- or import a submission, sign themselves up as a volunteer, resume a stopped role, bid, send
-- a call for bids, or reopen bidding while a venue is inactive; each raises RR028. Admins can
-- still configure the venue and staff its roles, invitees can still accept, and work already
-- in flight -- charges, compensation, closing submissions, thanks -- still settles.
-- Whether a venue is inactive: being configured, or closed. An inactive venue takes no new
-- work -- no submissions, no volunteers signing themselves up, no bids, no calls for bids, no
-- reopened bidding -- while its admins configure it, staff its roles, and settle what is
-- already in flight (#42). The triggers that enforce that call this, so the rule has one
-- definition. Invoker, not definer: venues are world-readable, so it needs no privilege of
-- its own, and it stays out of the definer grant sweep.
create or replace function public.isVenueInactive (_venueid uuid) RETURNS boolean LANGUAGE sql SECURITY INVOKER STABLE
set
	"search_path" to '' as $$
	select coalesce((select v.inactive is not null from public.venues v where v.id = _venueid), false);
$$;

alter function public.isVenueInactive (_venueid uuid) OWNER to postgres;

-- An inactive venue takes no new submissions and does not reopen bidding (#42). One trigger
-- rather than a check in each writer, because three paths insert submissions -- the client,
-- create_submission and bulk_import_submissions -- and a rule repeated three times is a rule
-- that will one day be missing from a fourth. A refused create_submission rolls back the
-- charges it wrote first, so nobody is billed for a submission that was never made.
--
-- Closing bidding stays allowed: it winds work down. Only reopening it is new work.
create or replace function public.submissions_need_active_venue () RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
set
	"search_path" to '' as $$
begin
	if tg_op = 'INSERT' or (old.bidding_closed and not new.bidding_closed) then
		if public.isVenueInactive(new.venue) then
			raise exception 'This venue is inactive' using errcode = 'RR028';
		end if;
	end if;
	return new;
end;
$$;

alter function public.submissions_need_active_venue () OWNER to postgres;

create trigger submissions_need_active_venue
before insert or update of bidding_closed on public.submissions for each row
execute function public.submissions_need_active_venue ();

-- An inactive venue takes no new volunteers who sign themselves up, and nobody resumes a role
-- they stopped (#42). Its staff can still put people in roles, and an invitee can still
-- accept, so a venue being configured can recruit its editors before it opens. Stewards count
-- as staff here: approve_venue_proposal seats the proposal's editors in a venue that starts
-- inactive. Accepting an invitation moves `accepted` off 'invited', which the resume test
-- below does not match.
--
-- A trigger rather than a policy clause, because create_volunteer and accept_role_invite are
-- SECURITY DEFINER and write past RLS; can_staff_role still sees the real caller, since
-- auth.uid() comes from the request, not the role a definer runs as.
create or replace function public.volunteers_need_active_venue () RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
set
	"search_path" to '' as $$
begin
	if (tg_op = 'INSERT' or (old.accepted = 'accepted' and not old.active and new.active))
		and public.isVenueInactive((select r.venueid from public.roles r where r.id = new.roleid))
		and not (public.can_staff_role(new.roleid) or public.isSteward()) then
		raise exception 'This venue is inactive' using errcode = 'RR028';
	end if;
	return new;
end;
$$;

alter function public.volunteers_need_active_venue () OWNER to postgres;

create trigger volunteers_need_active_venue
before insert or update of active on public.volunteers for each row
execute function public.volunteers_need_active_venue ();

-- Bids: one check added after the approver early return.
create or replace function public.enforce_bid_rules () RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
set
	"search_path" to '' as $$
declare
	_role public.roles;
	_budget record;
begin
	if not new.bid
		or new.scholar is distinct from (select auth.uid())
		or public.can_approve_assignment(new.submission, new.role) then
		return new;
	end if;

	perform pg_advisory_xact_lock(hashtextextended(new.scholar::text || new.role::text, 0));

	select * into _role from public.roles where id = new.role;

	-- An inactive venue takes no new bids (#42). Approvers' own assignments returned above:
	-- they staff work already in flight.
	if public.isVenueInactive(_role.venueid) then
		raise exception 'This venue is inactive' using errcode = 'RR028';
	end if;

	if not coalesce(_role.biddable, false) then
		raise exception 'This role does not take bids' using errcode = 'RR026';
	end if;

	if not exists (
		select 1 from public.submissions where id = new.submission and status = 'reviewing'
	) then
		raise exception 'This submission is not under review' using errcode = 'RR026';
	end if;

	if exists (
		select 1 from public.assignments
		where submission = new.submission and role = new.role and scholar = new.scholar
	) then
		raise exception 'This scholar already has a bid or assignment in this role' using errcode = 'RR026';
	end if;

	if (
		select count(*) from public.assignments
		where submission = new.submission and role = new.role and approved
	) >= _role.desired_assignments then
		raise exception 'This role is already full on this submission' using errcode = 'RR026';
	end if;

	select * into _budget from public._bid_limit(new.role, new.scholar);
	if _budget.bid_limit is not null and _budget.used >= _budget.bid_limit then
		raise exception 'Bid limit reached' using errcode = 'RR025';
	end if;

	return new;
end;
$$;

alter function public.enforce_bid_rules () OWNER to "postgres";

revoke
execute on function public.enforce_bid_rules ()
from
	public,
	anon;

-- Calls for bids: one check added after the authorization check. The revoke and grant travel
-- with the create or replace, since Supabase's default privileges re-grant anon EXECUTE on
-- every function creation.
create or replace function public.queue_call_for_bids (_role uuid, _note text) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_venueid uuid;
	_biddable boolean;
	_role_name text;
	_venue_title text;
	_venue_path text;
	_sender_name text;
	_sender_email text;
	_sender_label text;
	_recipients jsonb := '[]'::jsonb;
begin
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- The role, its venue, and whether bidding is even possible for it. A call for bids sent
	-- to a role the submissions page will not show bid buttons to is a message nobody can act
	-- on, so it is refused here rather than merely hidden in the interface.
	select r.venueid, r.biddable, r.name into _venueid, _biddable, _role_name
	from public.roles r where r.id = _role;
	if _venueid is null then
		raise exception 'Role not found';
	end if;
	if not _biddable then
		raise exception 'Bidding is not enabled for this role';
	end if;

	-- Who may ask. The same union that vets thank-you notes: the venue's admins run it, and
	-- the holders of its priority-0 role are its editors. Note isPriorityZero does not filter
	-- `active` -- it answers a question about authority, and an editor who has paused their
	-- own volunteering is still the venue's editor.
	if not (public.isAdmin(_venueid) or public.isPriorityZero(_venueid)) then
		raise exception 'You are not authorized to write to this venue''s volunteers';
	end if;

	-- An inactive venue asks nobody to bid (#42): there is nothing they could bid on.
	if public.isVenueInactive(_venueid) then
		raise exception 'This venue is inactive' using errcode = 'RR028';
	end if;

	-- The note. Bounded like a thank-you note, and for the same reason: it is one paragraph of
	-- somebody's prose inside branded mail, not a newsletter.
	if _note is null or char_length(btrim(_note)) = 0 then
		raise exception 'A call for bids cannot be empty';
	end if;
	if char_length(_note) > 1000 then
		raise exception 'A call for bids must be at most 1000 characters';
	end if;

	-- The sender must have a verified contact address, because Reply-To is resolved to it
	-- below. This is the one notice whose entire point is that a person is asking; a reply
	-- landing in the steward inbox instead of reaching the editor who wrote it would make the
	-- message a lie about itself. Refusing is better than sending a personal letter nobody can
	-- answer, and the hint lets the interface say why rather than showing a generic failure.
	select coalesce(nullif(btrim(s.name), ''), 'An editor'), s.email
	into _sender_name, _sender_email
	from public.scholars s where s.id = _caller;
	if _sender_email is null then
		raise exception 'A call for bids replies to you, so it needs a verified contact address'
			using hint = 'unverified';
	end if;

	-- The venue's title for the prose and its path for the link -- its web address once it has
	-- one, its id until then; both resolve.
	select v.title, coalesce(v.slug, v.id::text)
	into _venue_title, _venue_path
	from public.venues v where v.id = _venueid;

	-- The sender's own word for their job here. The venue's name for its top role is data, not
	-- a fixed title -- "Editor", "Area Chair", "Associate Editor" -- and is the same reasoning
	-- NewVolunteer applies. An admin who holds no role falls back to the generic word, since
	-- there is no role name to borrow.
	select coalesce(nullif(btrim(r.name), ''), 'an editor') into _sender_label
	from public.roles r
	join public.volunteers v on v.roleid = r.id
	where r.venueid = _venueid and r.priority = 0
		and v.scholarid = _caller and v.accepted = 'accepted'
	order by r.id
	limit 1;
	_sender_label := coalesce(_sender_label, 'an administrator');

	-- N private copies, never one cc'd thread. NewVolunteer uses cc because a welcome should
	-- converge into one conversation; the opposite is true here -- these recipients are
	-- reviewers who must not learn each other's addresses, and a biddable role routinely holds
	-- more than the 50 addresses Resend accepts on a single send.
	--
	-- Skipped: anyone who has stopped volunteering (they said not now), anyone not accepted,
	-- anyone without a verified address, anyone who silenced this notice, and the sender.
	insert into public.emails (event, scholar, sender, venue, email, reply_to, subject, message, args)
	select
		'CallForBids', s.id, _caller, _venueid, s.email, _sender_email,
		-- Null so the body is rendered at send time from the registry, which is the invariant
		-- that keeps prose out of the API.
		null, null,
		-- EVERY element must be non-null: the edge function validates args as
		-- z.array(z.string()), so one JSON null makes the whole body fail to parse, the
		-- function answers 400, and pg_net swallows it -- the mail simply never arrives.
		jsonb_build_array(
			coalesce(nullif(btrim(_venue_title), ''), 'a venue'),
			_sender_name,
			_sender_label,
			btrim(_note),
			coalesce(nullif(btrim(_role_name), ''), 'a volunteer'),
			_venue_path
		)
	from public.volunteers v
	join public.scholars s on s.id = v.scholarid
	where v.roleid = _role
		and v.active
		and v.accepted = 'accepted'
		and s.id <> _caller
		and s.email is not null
		and public.notification_allowed(s.id, 'CallForBids');

	-- The same predicate, because this is what the caller is told it sent.
	select coalesce(jsonb_agg(jsonb_build_object('name', s.name, 'email', s.email)), '[]'::jsonb)
	into _recipients
	from public.volunteers v
	join public.scholars s on s.id = v.scholarid
	where v.roleid = _role
		and v.active
		and v.accepted = 'accepted'
		and s.id <> _caller
		and s.email is not null
		and public.notification_allowed(s.id, 'CallForBids');

	-- The venue title travels back so the interface can render the subject for its "emailed X
	-- about Y" banners without looking it up again and risking a different answer. The mail
	-- itself is rendered at send time from the row; this is display copy only.
	return jsonb_build_object(
		'recipients', _recipients,
		'venue', coalesce(nullif(btrim(_venue_title), ''), 'a venue')
	);
end;
$function$;

alter function public.queue_call_for_bids (uuid, text) OWNER to "postgres";

-- The revoke travels WITH the create or replace, in the same migration: Supabase's default
-- privileges re-grant EXECUTE to anon on every function creation, so a revoke left in an
-- earlier migration is undone by this one.
revoke
execute on function public.queue_call_for_bids (uuid, text)
from
	public,
	anon;

grant
execute on function public.queue_call_for_bids (uuid, text) to authenticated;
