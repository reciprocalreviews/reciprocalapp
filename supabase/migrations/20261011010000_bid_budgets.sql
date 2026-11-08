-- Bid budgets. Some volunteers bid on every submission at a venue, which mails the
-- role's approvers once per bid. Each volunteer now has a budget per role
-- (public._bid_limit), and public.enforce_bid_rules refuses a bid past it (RR025), as
-- well as the bids the submissions page hid but the database accepted: on a role that
-- is not biddable, on a done submission, on a full role, or a second one (RR026).
-- Bids placed before this stay.
--
-- The revokes travel in this migration: Supabase's default privileges grant anon
-- EXECUTE on every function as it is created.

alter table public.roles
add column bid_limit_percent integer default 20,
add column bid_limit_floor integer default 10 not null;

alter table only public.roles
add constraint "roles_bid_limit_percent_check" check (
	bid_limit_percent is null
	or bid_limit_percent between 1 and 100
);

alter table only public.roles
add constraint "roles_bid_limit_floor_check" check (bid_limit_floor>=0);

-- _bid_limit: a volunteer's bid budget for a role, and how much of it is used.
--
-- Some volunteers bid on every submission at a venue, which no one has the expertise
-- for and which mails the role's approvers once per bid. So each volunteer has a
-- budget per role. Every bid counts against it -- pending, approved or declined --
-- while its submission is under review: a declined bid cannot be withdrawn, and
-- counting it is what stops bidding, being declined and bidding again elsewhere. A
-- submission marked done gives its bids back.
--
-- The limit is the role's percent of the venue's submissions under review, but never
-- less than its floor, so a small venue's volunteers may bid on everything. When the
-- volunteer has stated how many papers they will review, the limit is also at most
-- three times that. Null when the role has no budget.
--
-- Owner-only: it answers for any scholar. Clients read their own through
-- public.my_bid_budget; public.enforce_bid_rules reads it as the owner.
create or replace function public._bid_limit (_role uuid, _scholar uuid) returns table (used integer, bid_limit integer) language sql security definer stable
set
	"search_path" to '' as $$
	select
		(
			select count(*)::integer
			from public.assignments a
			join public.submissions s on s.id = a.submission
			where a.role = r.id and a.scholar = _scholar and a.bid and s.status = 'reviewing'
		),
		case
			when r.bid_limit_percent is null then null
			else least(
				greatest(
					r.bid_limit_floor,
					ceil(
						r.bid_limit_percent * (
							select count(*)
							from public.submissions s
							where s.venue = r.venueid and s.status = 'reviewing'
						) / 100.0
					)::integer
				),
				(
					select min(v.papers) * 3
					from public.volunteers v
					where v.roleid = r.id and v.scholarid = _scholar and v.active and v.accepted = 'accepted'
				)
			)
		end
	from public.roles r
	where r.id = _role;
$$;

alter function public._bid_limit (uuid, uuid) OWNER to "postgres";

revoke
execute on function public._bid_limit (uuid, uuid)
from
	public,
	anon,
	authenticated;

-- my_bid_budget: the caller's own bid budget for a role, for the submissions page.
create or replace function public.my_bid_budget (_role uuid) returns table (used integer, bid_limit integer) language sql security definer stable
set
	"search_path" to '' as $$
	select b.used, b.bid_limit from public._bid_limit(_role, (select auth.uid())) b;
$$;

alter function public.my_bid_budget (uuid) OWNER to "postgres";

revoke
execute on function public.my_bid_budget (uuid)
from
	public,
	anon;

grant
execute on function public.my_bid_budget (uuid) to authenticated;

-- enforce_bid_rules: what a scholar may bid on, checked when the bid is placed.
--
-- The INSERT policy checks only that the bidder volunteers for the role and that
-- bidding on the submission is open. The rest was the submissions page's to enforce,
-- so a direct API call could bid on a role that is not biddable, on a done
-- submission, on a role that is already full, or twice. This refuses all of those
-- (RR026) and a bid past the bidder's budget (RR025).
--
-- A trigger rather than a policy clause so that the client can say which rule
-- refused the bid, and rather than a unique index because it checks only new bids:
-- bids placed before these rules existed stay, as noise, and a scholar over budget
-- simply cannot bid again until they withdraw enough. The advisory lock serializes
-- one scholar's bids in one role, so two placed at once cannot both fit in the last
-- slot.
--
-- Only bids a scholar places for themselves: whoever may approve the assignment is
-- trusted to seat whom they like, and the service role is not checked.
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

create or replace trigger enforce_bid_rules
before insert on public.assignments for each row
execute function public.enforce_bid_rules ();
