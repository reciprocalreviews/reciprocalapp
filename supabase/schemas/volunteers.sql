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
create or replace function public.isPriorityZero (_venueid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
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

-- The single definition of "may this viewer see this volunteer record". Mirrors
-- nothing in TypeScript: the roster is read straight from the table, so this
-- policy is the only place the rule lives.
--
-- Keyed on the ROW ID rather than on (roleid, scholarid), which is the signature
-- it looks like it wants. This function is granted to anon and public.scholars is
-- world-readable, so a (roleid, scholarid) form would answer, for any scholar id
-- an anonymous caller cared to try, whether that scholar has completed an
-- assignment at the venue -- whether or not they volunteer for the role at all.
-- That is the disclosure public.token_events and public.tokens_as_of already
-- refuse on the grounds that it leaks reviewing activity venue anonymity is meant
-- to protect. Taking the row id confines the answer to a row whose id the caller
-- already holds, and holding it they could have selected the row instead.
--
-- SECURITY DEFINER is load-bearing: the branches below read public.volunteers and
-- public.assignments, and the same tests written inline in the policy would be
-- gated by those tables' own policies -- public.volunteers by this very one. The
-- table is owned by postgres and does not FORCE row level security, so the reads
-- bypass RLS and cannot recurse. Same reason public.can_claim_editor_role and
-- public.isAuthor are DEFINER.
--
-- STABLE because a policy predicate must be; see ARCHITECTURE.md on the
-- 20260830020000 sweep. It buys less here than usual -- the planner will not
-- inline a function that is both SECURITY DEFINER and carries a SET clause, and
-- _volunteer varies per row -- which is why the policy below tests the three cheap
-- cases inline and reaches this function only for a restricted role.
--
-- plpgsql rather than sql, for the same reason public.isConflicted is: a sql body
-- is parsed and resolved when the function is created, and this one reads
-- public.assignments, whose schema file loads AFTER this one. A sql body would
-- create fine during a migration replay and fail when the declarative schema is
-- rebuilt in dependency order.
create or replace function public.can_see_volunteer (_volunteer uuid) returns boolean language plpgsql security definer stable
set
	"search_path" to '' as $$
begin
	return exists (
		select 1
		from public.volunteers v
		join public.roles r on r.id = v.roleid
		where v.id = _volunteer
			and (
				-- Your own record. Load-bearing well beyond courtesy: the submissions
				-- SELECT policy and the assignments INSERT policy each read
				-- public.volunteers inline, so both are gated by this policy. Each
				-- filters to auth.uid(), so this branch is what keeps bidding and
				-- editor-claiming working at a role that publishes nobody.
				v.scholarid = (select auth.uid())
				-- An invitation is vetting nobody can award themselves, so holding an
				-- invite-only role is earned status and the setting does not apply.
				or r.invited
				-- The venue's editors are its public face rather than its grift
				-- surface. Also load-bearing: emailEditorsOf resolves the editor
				-- mailing list by reading this table with the CALLER's session, and
				-- its callers include authors, bidders and reviewers.
				or r.priority = 0
				-- The default, and true of every role until an admin opts out. Tested
				-- before the subquery branches below so the common case never runs one.
				or r.volunteer_visibility = 'all'
				-- Whoever staffs the role sees who is available to staff it: the venue's
				-- admins, its editors, and the holders of the role that approves this
				-- one. That last branch is venue-wide, which ARCHITECTURE.md records as
				-- the rule 20260913000000 deliberately removed -- from deciding who may
				-- ACT on a submission. This is a read of the roster and grants no
				-- authority; an approver who cannot see the pool cannot seat anyone from
				-- it.
				or public.isAdmin (r.venueid)
				or public.isPriorityZero (r.venueid)
				or (
					r.approver is not null
					and exists (
						select 1
						from public.volunteers av
						where av.roleid = r.approver
							and av.scholarid = (select auth.uid())
							and av.accepted = 'accepted'
					)
				)
				-- Otherwise the role's own setting decides. 'completed' means completed
				-- anywhere at this venue, not only in this role: contributing to the
				-- venue is what the listing is meant to recognize.
				--
				-- Joined through public.roles rather than read from assignments.venue.
				-- Both columns carry a foreign key, but assignments.venue is a
				-- denormalized copy the client supplies (createAssignment writes it
				-- directly) and nothing constrains it to agree with the venue of
				-- assignments.role -- no check, no trigger, and the INSERT policy never
				-- compares them. roles.venueid is the authoritative answer, and every
				-- other authorization rule in the schema reaches the venue the same way.
				or (
					r.volunteer_visibility = 'completed'
					and exists (
						select 1
						from public.assignments a
						join public.roles ar on ar.id = a.role
						where a.scholar = v.scholarid
							and ar.venueid = r.venueid
							and a.completed
					)
				)
			)
	);
end;
$$;

alter function public.can_see_volunteer (_volunteer uuid) OWNER to postgres;

revoke
execute on function public.can_see_volunteer (_volunteer uuid)
from
	public;

grant
execute on function public.can_see_volunteer (_volunteer uuid) to anon;

grant
execute on function public.can_see_volunteer (_volunteer uuid) to authenticated;

-- Per-role volunteer counts, regardless of who may see the volunteers themselves.
--
-- The policy above withholds rows the interface still has to count: the role card
-- badge, the "N volunteers" line, the venue's dashboard tile and the roster page's
-- section headings. A count derived from the filtered rows would quietly mean
-- something different to every reader, and would take a venue's recruiting signal
-- away along with the names -- which is not what hiding a roster is for. So this
-- answers the count and nothing else, the way public.submission_has_editor answers
-- one bit and public.currency_holder_counts answers an aggregate.
--
-- Safe to leave open to anon for the same reason currency_holder_counts is: it
-- discloses no name and no membership, only a number that is public today.
--
-- Counts EVERY row for the role, including inactive rows and declined invitations,
-- because that is what the interface counts today. Narrowing it would change every
-- number on the page for every viewer, which is a separate decision.
create or replace function public.venue_volunteer_counts (_venue uuid) returns table (role uuid, volunteer_count integer) language sql security definer stable
set
	"search_path" to '' as $$
	select r.id, count(v.id)::integer
	from public.roles r
	left join public.volunteers v on v.roleid = r.id
	where r.venueid = _venue
	group by r.id;
$$;

alter function public.venue_volunteer_counts (_venue uuid) OWNER to postgres;

revoke
execute on function public.venue_volunteer_counts (_venue uuid)
from
	public;

grant
execute on function public.venue_volunteer_counts (_venue uuid) to anon;

grant
execute on function public.venue_volunteer_counts (_venue uuid) to authenticated;

--------------------------------------
-- Security
alter table public.volunteers OWNER to postgres;

alter table public.volunteers ENABLE row LEVEL SECURITY;

-- Renamed rather than replaced in place: "anyone can view volunteers" was the
-- rule as well as the name, and leaving the name on a policy that no longer says
-- so would make the one place this schema states its rules in prose into the one
-- place it misstates them.
--
-- The three cheap tests are inline rather than left to can_see_volunteer, which
-- carries them too. public.roles is world-readable, so reading invited, priority
-- and the setting here discloses nothing and creates no oracle -- and it means a
-- venue that has not opted in pays one primary-key lookup per row instead of a
-- function call the planner cannot inline. The function remains the complete
-- rule; this is a fast path in front of it, not a substitute for it.
create policy "volunteer visibility follows the role's setting" on public.volunteers for
select
	to authenticated,
	anon using (
		(
			scholarid=(
				select
					auth.uid ()
			)
		)
		or exists (
			select
				1
			from
				public.roles r
			where
				r.id=volunteers.roleid
				and (
					r.invited
					or r.priority=0
					or r.volunteer_visibility='all'
				)
		)
		or public.can_see_volunteer (id)
	);

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

	-- Draw from the venue's reserve and move the grant to the scholar, minting
	-- only what the reserve cannot cover -- the same shape approve_transaction
	-- gives a venue-sourced transfer. _mint_shortfall rather than a count(*) and a
	-- pre-mint: the count could not see which of those tokens a concurrent payout
	-- had already locked, so a reserve that looked sufficient could still come up
	-- short. Taking first and minting the remainder is exact under concurrency,
	-- and drops a count(*) over the whole reserve from the volunteering path.
	--
	-- The last two arguments are what makes that mint accountable: _move_tokens
	-- records it as its own approved transaction crediting the reserve, so the
	-- venue's transactions still add up to the tokens it holds. Until 2026-08-30
	-- they did not, and reconcile_ledger's conservation check is what said so.
	-- _welcomer is the same person the transfer below names.
	_token_ids := public._move_tokens(
		_venue.currency, null, _venue.id, _scholar, null,
		_venue.welcome_amount, 'Insufficient tokens for the welcome grant', true,
		_welcomer, 'Minted to welcome a new volunteer'
	);

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
	public,
	anon,
	authenticated;

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
	_venue_path text;
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

	-- The venue's title for the prose and its path for the link. The path is the venue's web
	-- address once it has chosen one, and its id until then; both resolve, so a venue that
	-- has not named itself still gets a working link.
	select v.title, coalesce(v.slug, v.id::text)
	into _venue_title, _venue_path
	from public.venues v
	where v.id = _venueid;
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
		and public.notification_allowed(s.id, 'NewVolunteer');

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
			_venue_path,
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
		elsif _caller <> _scholarid and _accepted then
			-- The other side of that condition, and the case nobody was told about at all.
			--
			-- An administrator can seat somebody directly, with no invitation to accept. The
			-- notice above is deliberately suppressed for it (it is the admin's own action, so
			-- it is not news to the admins), and RoleInvite only fires where there IS an
			-- invitation -- so the person acquiring a venue commitment, and possibly a welcome
			-- grant with it, was the one party who heard nothing.
			--
			-- Consequential: it is a role with obligations, arriving unasked. No preference is
			-- consulted, for the same reason RoleInvite consults none.
			insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
			select
				'RoleEnrolled', s.id, _caller, _venueid, s.email, null, null,
				to_jsonb(array[
					r.name,
					v.title,
					coalesce(v.slug, v.id::text),
					s.id::text
				])
			from public.scholars s, public.roles r, public.venues v
			where s.id = _scholarid
				and r.id = _roleid
				and v.id = _venueid
				and s.email is not null;
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

--------------------------------------
-- queue_call_for_bids: a venue's editor writes to the volunteers of one biddable role,
-- asking them to come and bid.
--
-- This is the only mail RR sends that a person composes rather than an event triggers.
-- Everything else in the registry fires on something having already happened; nothing said
-- "we are short of bids and would like you to look", so a program chair's only recourse was
-- to export the volunteer list and mail it from outside RR -- losing the opt-out, the mail
-- log, the delivery tracking and the data download in one step.
--
-- It does NOT break the rule that a caller may not author a body. `_note` becomes ONE
-- template argument: the subject, the attribution, the "why you got this" line and the link
-- are owned by the CallForBids template and rendered at send time, and renderEmail escapes
-- the argument and defangs any URL scheme in it. So a caller chooses what one paragraph says
-- and nothing else -- not the subject, not the recipients, not a link. That is a stricter
-- contract than queue_thanks_emails, the only other template a person writes into, which
-- takes a fully pre-rendered subject and body.
--
-- Unlike queue_email, this authorizes against the venue. queue_email's documented residual is
-- that any authenticated caller may send any template to any scholar id; that is bounded
-- because the caller supplies no prose. Here the caller supplies prose, so the missing check
-- is not affordable and the venue relationship is verified before anything is written.
--
-- Returns {recipients: [{name, email}], venue: title}. The recipients are who was actually
-- reached rather than who was asked for -- a volunteer with no verified address, or one who
-- has silenced this notice, is skipped here and must not be counted in the banner. The title
-- rides along so the interface can label those banners without a second lookup.
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

--------------------------------------
-- call_for_bids_status: what the compose form needs to know before anything is sent.
--
-- Two things, neither of which the client can work out for itself:
--
-- `eligible` is how many people would actually receive it -- the same predicate the insert
-- above uses. The client can count a role's volunteers, but not which of them have a verified
-- address or have silenced the notice, so a client-side count would promise a number the
-- feedback banners then contradict. DESIGN.md's rule is that a number is reported before
-- submitting so that sending is a decision rather than a discovery.
--
-- `last_sent` / `last_sender` answer "has a colleague already done this?". There is
-- deliberately no rate limit -- an editor decides when their community needs asking -- so this
-- is information in service of that judgment, not a brake on it. It is here rather than read
-- from public.emails directly because that table's SELECT policy admits venue ADMINS only, so
-- a priority-0 editor could not see their own venue's mail log; widening the policy would
-- disclose every notice and address at the venue to a much larger group to answer one
-- question. Scoped like pending_email_verification(), which returns the caller's own row and
-- nothing else.
create or replace function public.call_for_bids_status (_role uuid) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_venueid uuid;
	_eligible integer;
	_last_sent timestamptz;
	_last_sender text;
begin
	if (select auth.uid()) is null then
		raise exception 'Authentication required';
	end if;

	select r.venueid into _venueid from public.roles r where r.id = _role;
	if _venueid is null then
		raise exception 'Role not found';
	end if;

	if not (public.isAdmin(_venueid) or public.isPriorityZero(_venueid)) then
		raise exception 'You are not authorized to read this venue''s call for bids';
	end if;

	select count(*) into _eligible
	from public.volunteers v
	join public.scholars s on s.id = v.scholarid
	where v.roleid = _role
		and v.active
		and v.accepted = 'accepted'
		and s.id <> (select auth.uid())
		and s.email is not null
		and public.notification_allowed(s.id, 'CallForBids');

	-- Venue-wide rather than per-role: a scholar often volunteers for several of a venue's
	-- roles, so "has this venue asked recently" is the question an editor is actually holding,
	-- and emails carries a venue but not a role.
	select e.time_sent, coalesce(nullif(btrim(s.name), ''), 'Someone')
	into _last_sent, _last_sender
	from public.emails e
	left join public.scholars s on s.id = e.sender
	where e.event = 'CallForBids' and e.venue = _venueid
	order by e.time_sent desc
	limit 1;

	return jsonb_build_object(
		'eligible', _eligible,
		'last_sent', _last_sent,
		'last_sender', _last_sender
	);
end;
$function$;

alter function public.call_for_bids_status (uuid) OWNER to "postgres";

revoke
execute on function public.call_for_bids_status (uuid)
from
	public,
	anon;

grant
execute on function public.call_for_bids_status (uuid) to authenticated;

alter publication supabase_realtime
add table volunteers;
