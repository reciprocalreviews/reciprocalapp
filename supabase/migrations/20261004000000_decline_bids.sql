-- #195: an approver may decline a bid, and must say why.
--
-- Adds the declined state to public.assignments, the decline_bid RPC that writes it, and
-- enforce_assignment_updates, which closes the own-row UPDATE policy's column gap (an
-- assignee could approve or complete their own assignment). Also narrows open-review
-- authors to APPROVED assignments, and stops a bidder deleting a declined bid.
-- See supabase/schemas/assignments.sql.

alter table public.assignments
add column declined_at timestamp with time zone default null,
add column declined_by uuid default null,
add column decline_reason text default null;

alter table public.assignments
add constraint assignments_decline_shape_check check ((declined_at is null)=(decline_reason is null)),
add constraint assignments_decline_reason_check check (
	decline_reason is null
	or char_length(btrim(decline_reason)) between 1 and 1000
),
add constraint assignments_decline_only_bids_check check (
	declined_at is null
	or (
		bid
		and not approved
		and not completed
	)
);

alter table only public.assignments
add constraint "assignments_declined_by_fkey" foreign KEY (declined_by) references public.scholars (id) on delete set null;

drop policy "assignees and approvers can see assignments" on public.assignments;

create policy "assignees and approvers can see assignments" on public.assignments for
select
	to authenticated using (
		(
			-- The assigned scholar can see their own assignment.
			(
				scholar=(
					select
						auth.uid () as "uid"
				)
			)
			-- Whoever may approve this assignment may see it, unless they are
			-- conflicted on the submission. can_approve_assignment covers venue
			-- admins itself.
			or (
				public.can_approve_assignment (submission, role)
				and not public.isConflicted (submission)
			)
			-- Open review: when the venue is not anonymous, the submission's
			-- authors may see who is assigned (unless they are conflicted). Only
			-- who is ASSIGNED: a pending or declined bid is a conversation between
			-- the bidder and the approvers, and a declined one carries the
			-- approver's reasons for turning a reviewer down.
			or (
				approved
				and (
					select
						not anonymous_assignments
					from
						public.venues
					where
						id=venue
				)
				and public.isAuthor (submission)
				and not public.isConflicted (submission)
			)
		)
	);

drop policy "assignees can delete assignments" on public.assignments;

-- A declined bid cannot be deleted by its bidder. The decline stands as the record of
-- the approver's answer, and deleting it would also let the bidder bid again as if it
-- had never been answered. An approver reverses a decline by approving the bid.
create policy "assignees can delete assignments" on "public"."assignments" for delete to authenticated using (
	(
		scholar=(
			select
				auth.uid () as "uid"
		)
		and declined_at is null
	)
);

-- The UPDATE policy above admits the assignee's own row with no limit on columns, because
-- RLS cannot be column-specific -- which let an assignee approve their own bid, complete
-- their own assignment, or move it to another role or submission. So, per column:
--
--   * scholar, role, submission, venue and bid never change after insert. An assignment is
--     about one person in one role on one paper; a different one is a different row.
--   * approved, completed and the decline columns are the approver's to set, under the
--     same rule as everything else an approver does: public.can_approve_assignment. An
--     approver who is also the assignee still passes, so seating oneself keeps working.
--   * preferenceid and compensation_requested_at are the assignee's own, and are the only
--     columns the app writes on its own row.
--
-- Approving a declined bid clears the decline: it is how an approver changes their mind,
-- and the decline-only-bids check would otherwise refuse the approval.
--
-- SECURITY INVOKER and gated on current_user = 'authenticated' on purpose. The SECURITY
-- DEFINER RPCs that write this table (complete_assignment, mark_submission_done,
-- decline_bid) run as postgres and authorize the caller themselves; this guards the one
-- path that has no other check, a client writing the row directly.
create or replace function public.enforce_assignment_updates () RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
set
	"search_path" to '' as $$
begin
	if new.approved and not old.approved then
		new.declined_at := null;
		new.declined_by := null;
		new.decline_reason := null;
	end if;

	if current_user <> 'authenticated' then
		return new;
	end if;

	if (new.scholar, new.role, new.submission, new.venue, new.bid)
		is distinct from (old.scholar, old.role, old.submission, old.venue, old.bid) then
		raise exception 'An assignment''s scholar, role, submission and bid cannot be changed'
			using errcode = 'RR018';
	end if;

	if (new.approved, new.completed, new.declined_at, new.declined_by, new.decline_reason)
		is distinct from (old.approved, old.completed, old.declined_at, old.declined_by, old.decline_reason)
		and not public.can_approve_assignment(old.submission, old.role) then
		raise exception 'Only an approver of this role may approve, complete or decline this assignment'
			using errcode = 'RR018';
	end if;

	return new;
end;
$$;

alter function public.enforce_assignment_updates () OWNER to "postgres";

revoke
execute on function public.enforce_assignment_updates ()
from
	public,
	anon;

create or replace trigger enforce_assignment_updates
before update on public.assignments for each row
execute function public.enforce_assignment_updates ();

-- decline_bid: an approver answers a bid with no, and says why.
--
-- The SECURITY DEFINER write path for the decline columns; enforce_assignment_updates
-- above refuses them to direct client writes from anyone who cannot approve. Requires a
-- reason because a decline is addressed to a person, and the reason is what makes it a
-- principled answer rather than a door shut in someone's face. Returns what the client
-- needs to send the BidDeclined notice.
--
-- RR017 when the bid is no longer pending (approved, completed, or already declined),
-- which is the race two approvers answering the same bid would otherwise both win.
create or replace function public.decline_bid (_assignment uuid, _reason text) returns jsonb language plpgsql security definer
set
	search_path to '' as $$
declare
	_caller uuid;
	_a public.assignments;
	_trimmed text;
begin
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	select * into _a from public.assignments where id = _assignment for update;
	if not found then
		raise exception 'Bid not found';
	end if;

	if not public.can_approve_assignment(_a.submission, _a.role)
		or public.isConflicted(_a.submission) then
		raise exception 'You are not authorized to decline this bid';
	end if;

	if not _a.bid or _a.approved or _a.completed or _a.declined_at is not null then
		raise exception 'This bid is no longer pending' using errcode = 'RR017';
	end if;

	_trimmed := btrim(coalesce(_reason, ''));
	if char_length(_trimmed) = 0 then
		raise exception 'A declined bid needs an explanation for the bidder';
	end if;
	if char_length(_trimmed) > 1000 then
		raise exception 'An explanation must be at most 1000 characters';
	end if;

	update public.assignments
	set declined_at = now(), declined_by = _caller, decline_reason = _trimmed
	where id = _assignment;

	return jsonb_build_object(
		'venue', _a.venue,
		'submission', _a.submission,
		'scholar', _a.scholar,
		'role', _a.role
	);
end;
$$;

alter function public.decline_bid (uuid, text) OWNER to "postgres";

revoke
execute on function public.decline_bid (uuid, text)
from
	public,
	anon;

grant
execute on function public.decline_bid (uuid, text) to authenticated;

