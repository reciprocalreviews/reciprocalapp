-- Bid notices go to the people who can approve the bid, not to every venue editor.
-- See public.bid_notice_recipients in supabase/schemas/assignments.sql.

-- Who is told that a bid arrived: the people who will answer it, not everyone who
-- edits the venue. Mailing every admin and priority-0 volunteer about every bid buried
-- the people who could act on it in mail about submissions they had nothing to do with.
--
-- The first tier with anyone in it wins: whoever holds the bid-on role's approving role
-- on this submission; failing that, the submission's priority-0 editor, who may approve
-- any role on it; failing that, the venue's admins, so a bid is never left unseen. Each
-- tier is the branch of can_approve_assignment above that describes it. The bidder and
-- anyone conflicted on the submission are dropped before a tier is chosen, so a tier
-- emptied by them falls through rather than silencing the notice.
--
-- SECURITY DEFINER because the bidder cannot see the approvers' assignments, and gated
-- on the caller having bid for this role on this submission, so it cannot be used to
-- learn who reviews or edits a submission one has no part in. plpgsql rather than sql so
-- the body is not resolved at creation: public.conflicts is declared after this file.
create or replace function public.bid_notice_recipients (_submission uuid, _role uuid) returns setof uuid language plpgsql security definer STABLE
set
	search_path to '' as $$
begin
	return query
	with
		candidates as (
			select a.scholar, 1 as tier
			from public.assignments a
			join public.roles target on target.id = _role
			where a.submission = _submission
			  and a.approved
			  and a.role = target.approver
			union all
			select a.scholar, 2 as tier
			from public.assignments a
			join public.roles r on r.id = a.role
			where a.submission = _submission
			  and a.approved
			  and r.priority = 0
			union all
			select unnest(v.admins), 3 as tier
			from public.submissions s
			join public.venues v on v.id = s.venue
			where s.id = _submission
		),
		eligible as (
			select c.scholar, c.tier
			from candidates c
			where c.scholar <> (select auth.uid())
			  and not exists (
				select 1
				from public.conflicts x
				where x.submissionid = _submission and x.scholarid = c.scholar
			  )
		)
	select distinct e.scholar
	from eligible e
	where e.tier = (select min(tier) from eligible)
	  and exists (
		select 1
		from public.assignments b
		where b.submission = _submission
		  and b.role = _role
		  and b.bid
		  and b.scholar = (select auth.uid())
	  );
end;
$$;

alter function public.bid_notice_recipients (uuid, uuid) OWNER to "postgres";

-- Explicitly revoked, not merely un-granted: Supabase's ALTER DEFAULT PRIVILEGES hands anon
-- EXECUTE on every function created in `public` at creation time.
revoke
execute on function public.bid_notice_recipients (uuid, uuid)
from
	public,
	anon;

grant
execute on function public.bid_notice_recipients (uuid, uuid) to authenticated;
