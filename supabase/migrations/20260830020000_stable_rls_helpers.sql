-- Token scaling, phase 3a: the RLS predicate helpers are VOLATILE.
--
-- Every one of these is a pure read used inside a row-level-security policy, and
-- every one was declared `LANGUAGE sql SECURITY DEFINER` with no volatility
-- marker -- which means VOLATILE, the default. Postgres will not hoist, cache or
-- fold a VOLATILE function, so each is re-executed FOR EVERY ROW the policy is
-- checked against, and several of them run a query of their own to answer
-- (isPriorityZero joins two tables; can_approve_assignment more).
--
-- `isSteward()` shows the cost most plainly because it takes no arguments at
-- all: as VOLATILE the planner still calls it once per row. Measured over 20,000
-- rows on a scale fixture, ~57ms; as STABLE it is hoisted to a single call and
-- the same query runs in well under a millisecond.
--
-- Nothing about their behaviour changes. STABLE promises only that the function
-- returns the same answer for the same arguments WITHIN one statement, which is
-- exactly what a policy predicate must already do to be coherent -- and two of
-- their siblings, submission_has_editor and venue_submission_editors, were
-- already declared STABLE, so this is the rest of the family catching up rather
-- than a new claim.
--
-- Bodies below are otherwise byte-identical to the current definitions.

create or replace function public.isAdmin (_venueid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
set
	"search_path" to '' as $$
    select ((select auth.uid()) = any((select admins from public.venues where id = _venueid)::uuid[]));
$$;

create or replace function public.isSteward () RETURNS boolean LANGUAGE "sql" SECURITY DEFINER STABLE
set
	"search_path" to '' as $$
    select (exists (select id from public.scholars where id = (select auth.uid()) and steward));
$$;

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

create or replace function "public"."isminter" ("_scholarid" "uuid", "_currencyid" "uuid") RETURNS boolean LANGUAGE "sql" SECURITY DEFINER STABLE
set
	"search_path" to '' as $$
    select (exists (select id from public.currencies where id = _currencyid and _scholarid = any(minters)));
$$;

create or replace function public.isAssigned (_submissionid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
set
	"search_path" to '' as $$
	select (exists (select id from public.assignments where submission=_submissionid and scholar=(select auth.uid()) and approved=true))
$$;

create or replace function public.isAuthor (_submissionid uuid) returns boolean language sql security definer STABLE
set
	"search_path" to '' as $$
	select exists (
		select 1 from public.submissions
		where id = _submissionid and (select auth.uid()) = any (authors)
	);
$$;

create or replace function public.isConflicted (_submissionid uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER STABLE
set
	"search_path" to '' as $$
begin
	return exists (
		select 1
		from public.conflicts
		where submissionid = _submissionid and scholarid = (select auth.uid())
	);
end;
$$;

create or replace function public.isInApproverChain (_roleid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
set
	"search_path" to '' as $$
	with recursive chain as (
		select approver as roleid, 1 as depth
		from public.roles
		where id = _roleid and approver is not null
		union all
		select r.approver, c.depth + 1
		from public.roles r
		join chain c on r.id = c.roleid
		where r.approver is not null and c.depth < 50
	)
	select exists (
		select 1
		from public.volunteers v
		join chain c on c.roleid = v.roleid
		where v.scholarid = (select auth.uid()) and v.accepted = 'accepted'
	);
$$;

create or replace function public.isRoleApproverVolunteer (_roleid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
set
	"search_path" to '' as $$
	select (
		exists (
			select id
			from public.volunteers
			where
				scholarid = (select auth.uid()) and
				roleid=(select approver from public.roles where id=_roleid) and
				accepted = 'accepted'
		)
	)
$$;

create or replace function public.can_approve_assignment (_submission uuid, _role uuid) returns boolean language sql security definer STABLE
set
	search_path to '' as $$
	select exists (
		-- A venue admin can approve anything in their venue.
		select 1
		from public.submissions s
		where s.id = _submission and public.isAdmin(s.venue)
	) or exists (
		-- The priority-0 editor OF THIS SUBMISSION can approve any role on it.
		select 1
		from public.assignments a
		join public.roles r on r.id = a.role
		where a.submission = _submission
		  and a.scholar = (select auth.uid())
		  and a.approved
		  and r.priority = 0
	) or exists (
		-- Whoever holds the role that approves the role in question, on this submission.
		select 1
		from public.assignments a
		join public.roles target on target.id = _role
		where a.submission = _submission
		  and a.scholar = (select auth.uid())
		  and a.approved
		  and target.approver is not null
		  and a.role = target.approver
	);
$$;

create or replace function public.can_claim_editor_role (_submission uuid, _role uuid) returns boolean language sql security definer STABLE
set
	search_path to '' as $$
	select exists (
		select 1
		from public.submissions s
		join public.roles r
			on r.id = _role and r.venueid = s.venue and r.priority = 0
		join public.volunteers v
			on v.roleid = r.id
			and v.scholarid = (select auth.uid())
			and v.active
			and v.accepted = 'accepted'
		where s.id = _submission
		  and not exists (
				select 1
				from public.assignments a
				join public.roles ar on ar.id = a.role
				where a.submission = _submission and ar.priority = 0
			)
	);
$$;
