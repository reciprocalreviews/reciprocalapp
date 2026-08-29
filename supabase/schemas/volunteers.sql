--------------------------------------
-- Schema
create type public.invited as enum('invited', 'accepted', 'declined');

alter type public.invited OWNER to postgres;

create table if not exists public.volunteers (
	-- The unique id of the role
	id uuid default gen_random_uuid() not null,
	-- The id of the scholar who volunteered
	scholarid uuid not null,
	-- The role they volunteered for
	roleid uuid not null,
	-- When this record was last updated
	created_at timestamp with time zone default now() not null,
	-- Relevant expertise provided by the scholar for the role
	expertise text not null,
	-- If the volunteer role is active or inactive, allowing scholars to unvolunteer, then revolunteer.
	-- Allows us to keep the record of volunteering without granting the venue's
	-- newcomer tokens more than once.
	active boolean default true not null,
	-- Whether this role as been accepted by the scholar
	accepted public.invited default 'accepted'::public.invited not null,
	-- The number of papers the volunteer is committing to review (soft cap; null = unspecified)
	papers integer
);

grant all on table public.volunteers to anon;

grant all on table public.volunteers to authenticated;

grant all on table public.volunteers to service_role;

-- `grant all` above confers TABLE-level UPDATE on every column, which a
-- column-level revoke cannot subtract, so remove it and re-grant only the
-- columns a volunteer may write. `scholarid` and `roleid` are identity: the row
-- records that this scholar volunteered for this role. The update policy's
-- USING expression covered `scholarid` but never mentioned `roleid`, so a
-- scholar could repoint their own row to a role at another venue — resetting the
-- per-venue count that decides the welcome grant (see create_volunteer below)
-- and earning it again. `accepted` is written only by the SECURITY DEFINER RPCs,
-- which grants do not constrain, because responding to an invitation is what
-- settles the welcome grant.
revoke
update on public.volunteers
from
	authenticated,
	anon;

grant
update (active, expertise, papers) on public.volunteers to authenticated;

-- `grant all` likewise confers TABLE-level DELETE that the deny policy alone
-- cannot subtract, so remove the privilege as well. Volunteering is a permanent
-- record that deactivates rather than disappears. service_role keeps its grant
-- for administrative and recovery work.
revoke delete on public.volunteers
from
	authenticated,
	anon;

alter table only public.volunteers
add constraint volunteers_pkey primary key (id);

alter table only public.volunteers
add constraint volunteers_roleid_fkey foreign KEY (roleid) references public.roles (id) on delete cascade;

alter table only public.volunteers
add constraint volunteers_scholarid_fkey foreign KEY (scholarid) references public.scholars (id) on delete cascade;

alter table only public.volunteers
add constraint volunteers_papers_check check (
	papers is null
	or papers>=0
);

--------------------------------------
-- Indexes
create index role_volunteer_index on public.volunteers using btree (roleid);

create index scholar_volunteer_index on public.volunteers using btree (scholarid);

--------------------------------------
-- Functions
-- True if the current scholar holds an accepted priority-0 role at the given venue.
-- Used by the tokens UPDATE policy to grant token-management authority.
create or replace function public.isPriorityZero (_venueid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER
set
	"search_path" to '' as $$
	select exists (
		select 1
		from public.volunteers v
		join public.roles r on r.id = v.roleid
		where v.scholarid = (select auth.uid())
			and v.accepted = 'accepted'
			and r.venueid = _venueid
			and r.priority = 0
	);
$$;

alter function public.isPriorityZero (_venueid uuid) OWNER to postgres;

grant all on FUNCTION public.isPriorityZero (_venueid uuid) to anon;

grant all on FUNCTION public.isPriorityZero (_venueid uuid) to authenticated;

grant all on FUNCTION public.isPriorityZero (_venueid uuid) to service_role;

--------------------------------------
-- Security
alter table public.volunteers OWNER to postgres;

alter table public.volunteers ENABLE row LEVEL SECURITY;

create policy "anyone can view volunteers" on public.volunteers for
select
	to authenticated,
	anon using (true);

create policy "admins can invite and volunteers if not invite only" on public.volunteers for INSERT to authenticated
with
	check (
		(
			public.isAdmin (
				(
					select
						roles.venueid
					from
						public.roles
					where
						(roles.id=volunteers.roleid)
				)
			)
			or (
				(
					(
						select
							auth.uid () as uid
					)=scholarid
				)
				and (
					not (
						select
							roles.invited
						from
							public.roles
						where
							(roles.id=volunteers.roleid)
					)
				)
			)
		)
	);

-- The WITH CHECK is spelled out rather than left to default from USING. It is
-- the same expression, so this changes nothing today; it is here so that a later
-- widening of USING — to admit venue admins, say — cannot silently widen what a
-- row is allowed to become along with it. What the row may not become is now
-- carried by the column grants above, which is where `roleid` is refused.
create policy "volunteers can update" on public.volunteers
for update
	to authenticated using (
		(
			(
				select
					auth.uid () as uid
			)=scholarid
		)
	)
with
	check (
		(
			(
				select
					auth.uid () as uid
			)=scholarid
		)
	);

-- Nobody deletes a volunteer record. This previously admitted venue admins and
-- the volunteering scholar, and no client path ever called it: CRUD declares no
-- deleteVolunteer, no RPC deletes one, and the only admin action that removes
-- volunteer rows is deleting the whole role, which cascades. What it permitted
-- was not small — the row is what stops a venue's welcome grant being made
-- twice, so deleting it and re-volunteering minted the welcome amount again.
-- Unvolunteering toggles `active` instead, which is why that column exists.
create policy "volunteers cannot be deleted" on public.volunteers for DELETE to authenticated using (false);

--------------------------------------
-- RPCs (defined in migration 20260608000000_atomic_crud.sql)
-- Internal helper: settle the welcome grant for a volunteer. Not granted to
-- any role — only reachable from the SECURITY DEFINER functions below. The
-- grant settles immediately (DESIGN: welcome tokens "should be minted and
-- given" on first volunteering): it draws from the venue's reserve, minting
-- only any shortfall, and records one approved venue->scholar transaction.
-- The amount is standing venue policy (venues.welcome_amount, granted at most
-- once per scholar per venue), so no per-grant minter approval is required;
-- minters still approve every other mint. No-op for payment-free venues.
--
-- Returns the number of tokens granted (0 on every no-op path), so the caller
-- can tell the scholar what they actually received. Whether a grant happens
-- turns on three conditions the client cannot evaluate reliably, and
-- re-deriving them there would put the rule in two places.
create or replace function public._welcome_volunteer (
	_welcomer uuid,
	_scholar uuid,
	_roleid uuid,
	_reason text
) returns integer language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_venue public.venues;
	_txn_id uuid;
	_available integer;
	_shortfall integer;
	_token_ids uuid[];
begin
	-- Find the venue that owns the role being volunteered for.
	select v.* into _venue
	from public.venues v
	join public.roles r on r.id = _roleid
	where v.id = r.venueid;
	-- Role or venue gone? Nothing to grant.
	if not found then
		return 0;
	end if;

	-- Payment-free venues have no tokens, and a zero welcome amount means there
	-- is nothing to grant — either way, do nothing.
	if _venue.payment_free or _venue.welcome_amount <= 0 then
		return 0;
	end if;

	-- Attribute both token writes below (the shortfall mint and the transfer) to
	-- the transaction recorded at the end. The id is generated up front because
	-- the tokens are written before the transaction row exists, and the
	-- token_events trigger reads app.txn at the moment of the write.
	_txn_id := gen_random_uuid();
	perform set_config('app.txn', _txn_id::text, true);

	-- Draw from the venue's reserve, minting only the shortfall into it first —
	-- the same shape approve_transaction gives a venue-sourced transfer.
	select count(*) into _available
	from public.tokens
	where currency = _venue.currency and venue = _venue.id;
	_shortfall := greatest(0, _venue.welcome_amount - _available);
	if _shortfall > 0 then
		insert into public.tokens (currency, venue, scholar)
		select _venue.currency, _venue.id, null from generate_series(1, _shortfall);
	end if;

	-- Choose the granted tokens and move them to the scholar.
	select array_agg(id) into _token_ids
	from (
		select id from public.tokens
		where currency = _venue.currency and venue = _venue.id
		order by id
		limit _venue.welcome_amount
	) sub;
	update public.tokens set venue = null, scholar = _scholar where id = any(_token_ids);

	-- Record the settled grant as one approved venue->scholar transaction.
	insert into public.transactions (
		id, creator, from_scholar, from_venue, to_scholar, to_venue,
		tokens, currency, purpose, status
	) values (
		_txn_id, _welcomer, null, _venue.id, _scholar, null,
		_token_ids, _venue.currency, _reason, 'approved'
	);

	-- Clear the attribution, so a later token write in this same database
	-- transaction that is NOT part of this grant is recorded as unattributed
	-- rather than borrowing this transaction's id.
	perform set_config('app.txn', '', true);

	-- Report what was granted, so the caller can say so precisely.
	return cardinality(_token_ids);
end;
$function$;

revoke
execute on function public._welcome_volunteer (uuid, uuid, uuid, text)
from
	public;

-- _notify_new_volunteer: tell a venue's top-priority role holders that a scholar has
-- volunteered for one of its open roles.
--
-- Owner-only, like public._welcome_volunteer beside it: this is a STEP of create_volunteer,
-- not an entry point. Its authorization is create_volunteer's, and that is the point --
-- there is no way to ask for this mail without also becoming a volunteer, and RR004 makes
-- that a once-per-(scholar, role) event forever, so it cannot be used to send twice.
--
-- Returns how many holders were addressed, 0 when nobody qualifies. Nothing reads the
-- number today; it exists so a caller can tell "nobody to tell" from "told somebody"
-- without querying the emails table.
create or replace function public._notify_new_volunteer (_venueid uuid, _roleid uuid, _scholarid uuid) returns integer language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_top_role uuid;
	_top_role_name text;
	_ids uuid[];
	_addrs text[];
	_reply_to text;
	_name text;
	_venue_title text;
	_role_name text;
begin
	-- The venue's top-priority role -- whatever this venue calls it. The name is data, so it
	-- is read here and handed to the template rather than assumed to be "Editor".
	-- `order by r.id limit 1` mirrors create_submission: priority is unique per venue by
	-- construction (create_role assigns max+1, and 20260828030000 renumbered the existing
	-- ones densely), and this stays deterministic if it ever isn't. Resolving a single role
	-- id also means a scholar who somehow holds two priority-0 roles is addressed once.
	select r.id, r.name into _top_role, _top_role_name
	from public.roles r
	where r.venueid = _venueid and r.priority = 0
	order by r.id
	limit 1;

	if _top_role is null then
		return 0;
	end if;

	-- The new volunteer. scholars.email holds only VERIFIED addresses, so null here means
	-- there is no reply path. The notice still goes out: the news is what matters, and a
	-- scholar with no contact address is precisely the one an editor needs the profile link
	-- for. The null is also what makes the branded footer fall back to naming the stewards
	-- instead of promising that a reply reaches a person.
	select coalesce(nullif(btrim(s.name), ''), 'A scholar'), s.email
	into _name, _reply_to
	from public.scholars s
	where s.id = _scholarid;

	select v.title into _venue_title from public.venues v where v.id = _venueid;
	select r.name into _role_name from public.roles r where r.id = _roleid;

	-- Who hears about it: ACTIVE, ACCEPTED holders of that role, with a verified contact
	-- address, who have not silenced this notice, and never the new volunteer themselves --
	-- someone can hold the top role here and still volunteer for another open one, and
	-- telling them their own news is noise.
	--
	-- Note this filters `active`, which public.isPriorityZero() does not. The app's own
	-- convention is the one followed here (see emailEditorsOf in SupabaseCRUD, which filters
	-- active and accepted): someone who has stopped volunteering should not be mailed about
	-- the venue's newcomers. Left as a comment rather than "fixed" in isPriorityZero,
	-- because that function answers a question about authority and this one answers a
	-- question about mail, and they are not obliged to agree.
	--
	-- Ordered by how long they have held the role, id breaking ties, so the To slot is
	-- deterministic and the venue's longest-standing holder is the one addressed. The
	-- tiebreak is load-bearing rather than decorative: supabase/seed.sql gives many
	-- volunteer rows an identical created_at to the microsecond, so ordering by it alone is
	-- genuinely ambiguous.
	select array_agg(s.id order by v.created_at, s.id),
	       array_agg(s.email order by v.created_at, s.id)
	into _ids, _addrs
	from public.volunteers v
	join public.scholars s on s.id = v.scholarid
	where v.roleid = _top_role
		and v.active
		and v.accepted = 'accepted'
		and s.id <> _scholarid
		and s.email is not null
		and not exists (
			select 1
			from public.notification_settings n
			where n.scholar = s.id and n.event = 'NewVolunteer' and not n.enabled
		);

	-- Nobody reachable. Saying nothing is right: the volunteering succeeded, and a venue
	-- whose top-role holders have no verified address is a venue configuration problem
	-- rather than a failure of volunteering. Note this is the DEFAULT state of a freshly
	-- approved venue, whose admins have not necessarily verified an address yet.
	if _addrs is null or cardinality(_addrs) = 0 then
		return 0;
	end if;

	-- Resend caps a message at 50 addresses across to + cc + bcc and rejects the whole send
	-- past that -- a rejection pg_net swallows, so the notice would vanish rather than fail
	-- loudly. No real venue has 50 people in its top role; this slice is what keeps that
	-- true rather than merely likely.
	if cardinality(_addrs) > 50 then
		_ids := _ids[1:50];
		_addrs := _addrs[1:50];
	end if;

	-- ONE row, one send, one thread: the first holder in To, the rest in Cc. Reply reaches
	-- the volunteer; Reply All reaches the volunteer and every other holder. A row per
	-- recipient would mean each of them receiving one copy addressed to them plus N-1 as a
	-- Cc, and the replies never converging.
	insert into public.emails (
		event, scholar, sender, venue, email, cc, reply_to, subject, message, args
	) values (
		'NewVolunteer',
		_ids[1],
		-- Attribution, as queue_email records its caller. This makes the row readable by the
		-- volunteer through the SELECT policy's `sender` branch, which leaks nothing:
		-- scholars.email is already readable by anyone signed in. thanks.sql nulls its
		-- sender because reviewer anonymity depends on it; nothing here is anonymous -- the
		-- volunteer is named in the body.
		_scholarid,
		_venueid,
		_addrs[1],
		-- nullif so a lone holder yields NULL rather than the empty array the check
		-- constraint in part 1 forbids.
		nullif(_addrs[2:], '{}'::text[]),
		_reply_to,
		-- Null so the body is rendered at send time from the template registry, which is the
		-- invariant that keeps prose out of the API.
		null,
		null,
		-- EVERY element must be non-null. jsonb_build_array with a NULL yields JSON null;
		-- the edge function validates args as z.array(z.string()), so one null makes the
		-- WHOLE body fail to parse, the function answers 400, and pg_net swallows it -- the
		-- email simply never arrives, with nothing on screen to say so. scholars.name is
		-- nullable (a fresh ORCID account has none) and role and venue titles default to '',
		-- so every one of them is coalesced.
		jsonb_build_array(
			_name,
			coalesce(nullif(btrim(_role_name), ''), 'volunteer'),
			coalesce(nullif(btrim(_venue_title), ''), 'a venue'),
			_scholarid::text,
			_venueid::text,
			coalesce(nullif(btrim(_top_role_name), ''), 'top')
		)
	);

	return cardinality(_addrs);
end;
$function$;

alter function public._notify_new_volunteer (uuid, uuid, uuid) OWNER to "postgres";

revoke
execute on function public._notify_new_volunteer (uuid, uuid, uuid)
from
	public,
	anon,
	authenticated;

-- create_volunteer: insert a volunteer record and, when this is the scholar's
-- first role at the role's venue and compensation is requested, settle the
-- welcome grant — atomically. SECURITY DEFINER, re-implementing the volunteers
-- INSERT policy (venue admin, or self for a non-invite-only role).
create or replace function public.create_volunteer (
	_scholarid uuid,
	_roleid uuid,
	_accepted boolean,
	_compensate boolean,
	_papers integer
) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_venueid uuid;
	_invited boolean;
	_existing_count integer;
	_volunteer_id uuid;
	_granted integer := 0;
begin
	-- Identify and require an authenticated caller.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- Look up the role's venue and whether it is invite-only.
	select venueid, invited into _venueid, _invited from public.roles where id = _roleid;
	if _venueid is null then
		raise exception 'Role not found';
	end if;

	-- A venue admin may add anyone; otherwise a scholar may only add themselves,
	-- and only to a role that is not invite-only.
	if not (public.isAdmin(_venueid) or (_caller = _scholarid and not _invited)) then
		raise exception 'You are not authorized to volunteer for this role';
	end if;

	-- No duplicate volunteering for the same role. RR004 surfaces the specific
	-- "already volunteered" message.
	if exists (select 1 from public.volunteers where scholarid = _scholarid and roleid = _roleid) then
		raise exception 'Already volunteered for this role' using errcode = 'RR004';
	end if;

	-- Welcome tokens are standing policy of one venue, so they are granted once
	-- per scholar per venue: someone who volunteered elsewhere is still a
	-- newcomer here, and this venue's currency is not one they already hold.
	-- Count only their existing volunteer rows at this venue, before inserting
	-- the new one.
	select count(*) into _existing_count
	from public.volunteers v
	join public.roles r on r.id = v.roleid
	where v.scholarid = _scholarid and r.venueid = _venueid;

	-- Create the volunteer record.
	insert into public.volunteers (scholarid, roleid, active, accepted, expertise, papers)
	values (
		_scholarid, _roleid, _accepted,
		case when _accepted then 'accepted'::public.invited else 'invited'::public.invited end,
		'', _papers
	) returning id into _volunteer_id;

	-- First role at this venue and compensation requested? Settle the welcome
	-- grant in the same transaction, so the volunteer can never exist without it.
	if _existing_count = 0 and _compensate then
		_granted := public._welcome_volunteer(_caller, _scholarid, _roleid, 'Welcome tokens for volunteering');
	end if;

	-- Tell the venue's top-priority role holders -- but only when a scholar volunteered for
	-- THEMSELVES for an OPEN role. That is the news: an admin adding someone is not news to
	-- the admins, and an invitation is answered through accept_role_invite, which stays
	-- deliberately silent because the people who would be told are the ones who sent it.
	--
	-- The predicate is the authorization branch above, reused verbatim rather than restated,
	-- so "may this person volunteer here" and "is this worth telling anyone" cannot drift
	-- apart. It deliberately does not also require _accepted: the interface always passes
	-- true on this path (VolunteerStatus.svelte), and a hand-rolled call passing false makes
	-- a self-invitation that accept_role_invite later resolves without a second notice -- a
	-- dead corner worth accepting to keep one predicate instead of two nearly-identical ones.
	--
	-- Best effort, like delivery itself (see send_email): the volunteer record and its
	-- welcome grant are what must not be lost, and no failure to compose a notice may roll
	-- them back.
	begin
		if _caller = _scholarid and not _invited then
			perform public._notify_new_volunteer(_venueid, _roleid, _scholarid);
		end if;
	exception when others then
		raise warning 'create_volunteer: volunteer % was created but the venue could not be notified: % (%)',
			_volunteer_id, sqlerrm, sqlstate;
	end;

	-- Return the new volunteer id and what the grant actually came to.
	return jsonb_build_object('volunteer_id', _volunteer_id, 'welcome_granted', _granted);
end;
$function$;

revoke
execute on function public.create_volunteer (uuid, uuid, boolean, boolean, integer)
from
	public;

grant
execute on function public.create_volunteer (uuid, uuid, boolean, boolean, integer) to authenticated;

-- accept_role_invite: respond to a role invitation and, when accepting a first
-- role at the role's venue, settle the welcome grant — atomically. SECURITY
-- DEFINER, re-implementing the volunteers UPDATE policy (only the volunteering
-- scholar).
create or replace function public.accept_role_invite (_volunteer_id uuid, _response public.invited) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_v public.volunteers;
	_venueid uuid;
	_total integer;
	_granted integer := 0;
begin
	-- Identify and require an authenticated caller.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- Load the invitation; only the invited scholar may respond to it.
	select * into _v from public.volunteers where id = _volunteer_id;
	if not found then
		raise exception 'Volunteer record not found';
	end if;
	if _caller <> _v.scholarid then
		raise exception 'You can only respond to your own invitations';
	end if;

	-- Count the scholar's volunteer rows at this role's venue to detect a
	-- first-role acceptance here; the grant is once per scholar per venue. The
	-- invitation row already exists, so a count of 1 means it is their only one.
	select venueid into _venueid from public.roles where id = _v.roleid;
	select count(*) into _total
	from public.volunteers v
	join public.roles r on r.id = v.roleid
	where v.scholarid = _v.scholarid and r.venueid = _venueid;

	-- Apply the response and (re)activate the record.
	update public.volunteers set active = true, accepted = _response where id = _volunteer_id;

	-- Accepting a first invitation at this venue earns its welcome grant,
	-- recorded atomically.
	if _total = 1 and _v.accepted = 'invited' and _response = 'accepted' then
		_granted := public._welcome_volunteer(_v.scholarid, _v.scholarid, _v.roleid, 'Welcome tokens for accepting role invite');
	end if;

	-- Return the volunteer id that was updated and what the grant came to.
	return jsonb_build_object('volunteer_id', _volunteer_id, 'welcome_granted', _granted);
end;
$function$;

revoke
execute on function public.accept_role_invite (uuid, public.invited)
from
	public;

grant
execute on function public.accept_role_invite (uuid, public.invited) to authenticated;

alter publication supabase_realtime
add table volunteers;
