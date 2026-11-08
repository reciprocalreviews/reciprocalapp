-- Anyone who may answer bids on a submission may open or close its bidding, not just
-- its priority-0 editor: an Associate Editor approving its Reviewer bids could not.
-- bidding_closed leaves the client column grant and is written by an RPC that
-- authorizes through can_approve_assignment, so approvers gain this one switch and
-- nothing else the submissions UPDATE policy would have given them.
revoke
update on public.submissions
from
	authenticated;

grant
update (
	venue,
	externalid,
	previousid,
	previous,
	submission_type,
	authors,
	payments,
	transactions,
	title,
	expertise
) on public.submissions to authenticated;

create or replace function public.set_submission_open_for_bidding (_submission uuid, _open boolean) returns void language plpgsql security definer
set
	"search_path" to '' as $$
begin
	if (select auth.uid()) is null then
		raise exception 'Authentication required' using errcode = '42501';
	end if;

	if not exists (
		select 1
		from public.submissions s
		join public.roles r on r.venueid = s.venue
		where s.id = _submission
			and r.biddable
			and public.can_approve_assignment(_submission, r.id)
	) then
		raise exception 'Only someone who may answer bids on this submission may open or close its bidding'
			using errcode = '42501';
	end if;

	update public.submissions set bidding_closed = not _open where id = _submission;
end;
$$;

alter function public.set_submission_open_for_bidding (uuid, boolean) OWNER to "postgres";

revoke
execute on function public.set_submission_open_for_bidding (uuid, boolean)
from
	public,
	anon;

grant
execute on function public.set_submission_open_for_bidding (uuid, boolean) to authenticated;

-- No client can write bidding_closed any longer, so the author-edit trigger goes back
-- to guarding the author list alone.
create or replace function public.enforce_submission_author_edits () RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
set
	"search_path" to '' as $$
begin
	if (
		new.authors is distinct from old.authors
		or new.payments is distinct from old.payments
		or new.transactions is distinct from old.transactions
	) and not exists (
		select 1
		from public.assignments a
		join public.roles r on r.id = a.role
		where a.submission = old.id
			and a.scholar = (select auth.uid())
			and a.approved = true
			and r.priority = 0
	) then
		raise exception 'Only priority-0 assigned scholars may change the author list';
	end if;
	return new;
end;
$$;

alter function public.enforce_submission_author_edits () OWNER to "postgres";

-- Re-created, so re-revoked: see 20260831000000 and definer_grants.sql.
revoke
execute on function public.enforce_submission_author_edits ()
from
	public,
	anon,
	authenticated;
