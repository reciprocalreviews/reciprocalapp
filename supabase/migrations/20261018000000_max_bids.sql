-- Max bids. The bid budget was a percent of the venue's submissions under review,
-- with a floor and a cap of three times the papers a volunteer said they would
-- review. That was more than venues needed: few people review more than a handful.
-- Each role now has one fixed number, max_bids, which a program committee can size
-- to its submission count. Roles that had no budget keep none; the rest get 5.
--
-- The revoke travels in this migration: Supabase's default privileges grant anon
-- EXECUTE on a function every time it is re-created.

alter table public.roles
add column max_bids integer default 5;

alter table only public.roles
add constraint "roles_max_bids_check" check (
	max_bids is null
	or max_bids>=1
);

update public.roles
set
	max_bids = null
where
	bid_limit_percent is null;

-- _bid_limit: a volunteer's bid budget for a role, and how much of it is used.
--
-- Some volunteers bid on every submission at a venue, which no one has the expertise
-- for and which mails the role's approvers once per bid. So each volunteer has a
-- budget per role. Every bid counts against it -- pending, approved or declined --
-- while its submission is under review: a declined bid cannot be withdrawn, and
-- counting it is what stops bidding, being declined and bidding again elsewhere. A
-- submission marked done gives its bids back.
--
-- The limit is the role's max_bids, a fixed number, so that volunteers bid on the
-- submissions they are most qualified to review. Null when the role has no limit.
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
		r.max_bids
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

alter table public.roles
drop constraint "roles_bid_limit_percent_check",
drop constraint "roles_bid_limit_floor_check";

alter table public.roles
drop column bid_limit_percent,
drop column bid_limit_floor;
