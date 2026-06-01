-- RLS policy corrections (issue #79).
--
-- Surfaced while building the pgTAP RLS test suite: several policies granted
-- more or less than intended. This migration corrects them and adds the helper
-- functions and triggers the corrected policies depend on. Mirrors the edits in
-- supabase/schemas/*.sql.

--------------------------------------
-- Helper functions
--------------------------------------

-- True if the current scholar holds an accepted priority-0 role at the venue.
create or replace function public.isPriorityZero (_venueid uuid) returns boolean language sql security definer
set "search_path" to '' as $$
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

alter function public.isPriorityZero (_venueid uuid) owner to postgres;
grant all on function public.isPriorityZero (_venueid uuid) to anon;
grant all on function public.isPriorityZero (_venueid uuid) to authenticated;
grant all on function public.isPriorityZero (_venueid uuid) to service_role;

-- True if the current scholar is an accepted volunteer on any role in the
-- approver chain ABOVE the given role.
create or replace function public.isInApproverChain (_roleid uuid) returns boolean language sql security definer
set "search_path" to '' as $$
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

alter function public.isInApproverChain (_roleid uuid) owner to postgres;
grant all on function public.isInApproverChain (_roleid uuid) to anon;
grant all on function public.isInApproverChain (_roleid uuid) to authenticated;
grant all on function public.isInApproverChain (_roleid uuid) to service_role;

-- True if the current scholar has a declared conflict on the submission.
create or replace function public.isConflicted (_submissionid uuid) returns boolean language plpgsql security definer
set "search_path" to '' as $$
begin
	return exists (
		select 1
		from public.conflicts
		where submissionid = _submissionid and scholarid = (select auth.uid())
	);
end;
$$;

alter function public.isConflicted (_submissionid uuid) owner to postgres;
grant all on function public.isConflicted (_submissionid uuid) to anon;
grant all on function public.isConflicted (_submissionid uuid) to authenticated;
grant all on function public.isConflicted (_submissionid uuid) to service_role;

-- True if the current scholar authors the submission. SECURITY DEFINER so the
-- assignments SELECT policy can read submissions.authors without triggering the
-- submissions RLS policy (mutual reference would be infinite recursion).
create or replace function public.isAuthor (_submissionid uuid) returns boolean language sql security definer
set "search_path" to '' as $$
	select exists (
		select 1 from public.submissions
		where id = _submissionid and (select auth.uid()) = any (authors)
	);
$$;

alter function public.isAuthor (_submissionid uuid) owner to postgres;
grant all on function public.isAuthor (_submissionid uuid) to anon;
grant all on function public.isAuthor (_submissionid uuid) to authenticated;
grant all on function public.isAuthor (_submissionid uuid) to service_role;

-- Author-list lock for submissions (see trigger below).
create or replace function public.enforce_submission_author_edits () returns trigger language plpgsql security definer
set "search_path" to '' as $$
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

alter function public.enforce_submission_author_edits () owner to postgres;

--------------------------------------
-- Fix A: restrict anon read on compensation, preference_levels, tokens
--------------------------------------

drop policy if exists "anyone can read compensation" on public.compensation;
create policy "authenticated scholars can read compensation" on public.compensation for
select to authenticated using (true);

drop policy if exists "anyone can view preference levels" on public.preference_levels;
create policy "authenticated scholars can view preference levels" on public.preference_levels for
select to authenticated using (true);

drop policy if exists "tokens are public" on public.tokens;
create policy "tokens are visible to authenticated scholars" on public.tokens for
select to authenticated using (true);

--------------------------------------
-- Policy renames (behavior unchanged; names now match intent)
--------------------------------------

drop policy if exists "anyone can create currencies" on public.currencies;
create policy "only stewards can create currencies" on public.currencies for insert to authenticated
with check (public.issteward ());

drop policy if exists "admins can update proposals" on public.supporters;
create policy "supporters can update their own support" on public.supporters
for update to authenticated using ((select auth.uid ()) = scholarid);

--------------------------------------
-- Fix B: assignment visibility = assignee, or approver chain / admin minus conflicted
--------------------------------------

drop policy if exists "assignees and approvers can see assignments" on public.assignments;
create policy "assignees and approvers can see assignments" on public.assignments for
select to authenticated using (
	(scholar = (select auth.uid ()))
	or (
		(public.isInApproverChain (role) or public.isAdmin (venue))
		and not public.isConflicted (submission)
	)
	-- Open review: when the venue is not anonymous, the submission's authors may
	-- see who is assigned (unless conflicted).
	or (
		(select not anonymous_assignments from public.venues where id = venue)
		and public.isAuthor (submission)
		and not public.isConflicted (submission)
	)
);

--------------------------------------
-- Fix D: token ownership update authority (drop minters, add priority-0 roles)
--------------------------------------

drop policy if exists "only token owners, venue admins, and minters can update a token" on public.tokens;
create policy "owners, admins, and priority-0 roles can update tokens" on public.tokens
for update to authenticated using (
	((scholar is not null) and (select auth.uid ()) = scholar)
	or ((venue is not null) and (public.isAdmin (venue) or public.isPriorityZero (venue)))
)
with check (true);

--------------------------------------
-- Fix E: transactions are an immutable record except status/decline/tokens.
-- Also fixes the analogous latent bug on submissions.status/completed_at: a
-- column-level revoke is a no-op while authenticated holds the table-level
-- UPDATE from `grant all`. Remove the table-level UPDATE and re-grant only the
-- mutable columns.
--------------------------------------

revoke update on public.transactions from authenticated;
grant update (status, tokens, decliner, decline_reason) on public.transactions to authenticated;

revoke update on public.submissions from authenticated;
grant update (
	venue, externalid, previousid, previous, submission_type, authors, payments, transactions, title, expertise
) on public.submissions to authenticated;

--------------------------------------
-- Fix C: lock the submission author list to priority-0 assigned scholars
--------------------------------------

create or replace trigger enforce_submission_author_edits before update on public.submissions
for each row execute function public.enforce_submission_author_edits ();

--------------------------------------
-- Fix F: email sender visibility
--------------------------------------

alter table public.emails add column if not exists sender uuid;
alter table public.emails drop constraint if exists emails_sender_fkey;
alter table public.emails add constraint emails_sender_fkey foreign key (sender) references public.scholars (id);

drop policy if exists "recipients and venue admins can see the emails sent" on public.emails;
create policy "senders, recipients, and venue admins can see the emails sent" on public.emails for
select to authenticated using (
	((select auth.uid ()) = scholar)
	or ((select auth.uid ()) = sender)
	or ((venue is not null) and public.isAdmin (venue))
);
