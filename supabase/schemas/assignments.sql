--------------------------------------
-- Schema
-- Individuals who could be assigned to review a particular paper
create table if not exists public.assignments (
	-- The unique ID of the bid
	id uuid default gen_random_uuid() not null,
	-- The venue to which this assignment corresponds
	venue uuid not null,
	-- The submission bid on
	submission uuid not null,
	-- The scholar who bid
	scholar uuid not null,
	-- The role for which the bid occurred
	role uuid not null,
	-- True if a bid by the reviewer.
	bid boolean default false not null,
	-- True if the assignment has been approved
	approved boolean default false not null,
	-- True if the assignment has been completed
	completed boolean default false not null,
	-- The bidder's chosen preference level for this submission. Only meaningful
	-- when bid=true and the venue has defined preference levels; null otherwise.
	preferenceid uuid,
	-- Timestamp when the assignment was created
	created_at timestamp with time zone default timezone ('utc'::text, now()) not null,
	-- When the scholar requested compensation for this assignment (null until
	-- they do). Distinguishes finished work awaiting an approver from a review
	-- still in progress, so the daily remind function can nag approvers about
	-- the former without nagging them about the latter. Stamped by the scholar
	-- themselves (their own-row UPDATE policy permits it).
	compensation_requested_at timestamp with time zone default null
);

alter table public.assignments OWNER to "postgres";

alter table only public.assignments
add constraint "assignments_pkey" primary key (id);

alter table only public.assignments
add constraint "assignments_role_fkey" foreign KEY (role) references public.roles (id) on delete cascade;

alter table only public.assignments
add constraint "assignments_scholar_fkey" foreign KEY (scholar) references public.scholars (id) on delete cascade;

alter table only public.assignments
add constraint "assignments_submission_fkey" foreign KEY (submission) references public.submissions (id) on delete cascade;

alter table only public.assignments
add constraint "assignments_venue_fkey" foreign KEY (venue) references public.venues (id) on delete cascade;

alter table only public.assignments
add constraint "assignments_preferenceid_fkey" foreign KEY (preferenceid) references public.preference_levels (id) on delete set null;

--------------------------------------
-- Indexes
create index "assignments_scholar_index" on public.assignments using "btree" (scholar);

create index "assignments_submission_index" on public.assignments using "btree" (submission);

create index "idx_assignments_completed" on public.assignments using "btree" (completed);

--------------------------------------
-- Functions
-- True if the current scholar is an ACCEPTED VOLUNTEER on the role that approves
-- the given role, anywhere in the venue. This is NOT the same rule as
-- public.can_approve_assignment below, and the name says so on purpose: this one
-- is venue-wide and volunteer-based, with no admin branch, no priority-0 editor
-- branch, and no submission. It is the USING clause of the assignments UPDATE
-- policy, where an AE must be able to approve a bid on a submission they hold no
-- assignment on — so it cannot be narrowed to match the other rule without
-- revoking that. See migration 20260816010000 for the full reasoning.
create or replace function public.isRoleApproverVolunteer (_roleid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER
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

alter function public.isRoleApproverVolunteer (uuid) OWNER to "postgres";

grant all on FUNCTION public.isRoleApproverVolunteer (uuid) to "anon";

grant all on FUNCTION public.isRoleApproverVolunteer (uuid) to "authenticated";

grant all on FUNCTION public.isRoleApproverVolunteer (uuid) to "service_role";

-- The single definition of "may this scholar approve an assignment for this role
-- on this submission" — a venue admin, the submission's priority-0 editor, or the
-- holder of the approving role, each requiring an APPROVED ASSIGNMENT on this
-- submission. Mirrored in TypeScript by src/lib/data/canApproveAssignment.ts.
create or replace function public.can_approve_assignment (_submission uuid, _role uuid) returns boolean language sql security definer
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

alter function public.can_approve_assignment (uuid, uuid) OWNER to "postgres";

revoke
execute on function public.can_approve_assignment (uuid, uuid)
from
	public;

grant
execute on function public.can_approve_assignment (uuid, uuid) to authenticated;

-- A THIRD rule in this family, and again deliberately not the same question as the two
-- above: "may I take this submission?", not "may I approve it for someone else?".
--
-- It exists because the venue's own editors could not seat themselves. The priority-0
-- role has no approver, so isRoleApproverVolunteer is never true for it, and
-- can_approve_assignment's editor branch requires an approved priority-0 assignment on
-- the very submission being claimed — which is self-perpetuating. That left isAdmin() as
-- the only way anyone became the first editor on a submission, so an Editor-role
-- volunteer who was not also a venue admin could be told a submission needed them and be
-- unable to do anything about it.
--
-- Narrow on every axis: the caller only, the venue's priority-0 role only, and only while
-- the submission has no priority-0 assignment at all. It cannot seat anyone else, seat
-- anyone in another role, or displace an editor who is already there.
--
-- SECURITY DEFINER is load-bearing rather than habitual: the emptiness test reads
-- public.assignments, which is itself RLS-gated, so the same test written inline in the
-- policy would see only the rows the claimer may select and would report "no editor" for
-- a submission that already has one. Mirrored in TypeScript by
-- src/lib/data/canClaimEditor.ts.
create or replace function public.can_claim_editor_role (_submission uuid, _role uuid) returns boolean language sql security definer
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

alter function public.can_claim_editor_role (uuid, uuid) OWNER to "postgres";

revoke
execute on function public.can_claim_editor_role (uuid, uuid)
from
	public;

grant
execute on function public.can_claim_editor_role (uuid, uuid) to authenticated;

-- Whether a submission has anyone in a priority-0 role, and nothing else about who.
--
-- The venue's editors can see their venue's submissions but none of its assignments, so
-- the submissions list had no way to tell whether a submission already had an editor —
-- it inferred from the assignment rows it could see, and for a non-admin editor that is
-- none of them, so every submission looked unclaimed. Widening the assignments policy
-- would have handed reviewer identities to more people to answer a yes/no question, so
-- this answers the question instead.
--
-- SECURITY DEFINER, so it sees past the assignments policy; the pair below is what keeps
-- that narrow. It discloses one bit, and only about a submission whose id the caller
-- already holds.
create or replace function public.submission_has_editor (_submission uuid) returns boolean language sql security definer stable
set
	"search_path" to '' as $$
	select exists (
		select 1
		from public.assignments a
		join public.roles r on r.id = a.role
		where a.submission = _submission and r.priority = 0
	);
$$;

alter function public.submission_has_editor (uuid) OWNER to "postgres";

revoke
execute on function public.submission_has_editor (uuid)
from
	public;

grant
execute on function public.submission_has_editor (uuid) to authenticated;

-- The list form, and the one the application actually calls. SECURITY INVOKER, so the
-- scan of public.submissions runs under the caller's own policy: a caller gets exactly
-- one row per submission they may already see, each carrying that one bit.
create or replace function public.venue_submission_editors (_venue uuid) returns table (submission uuid, has_editor boolean) language sql security invoker stable
set
	"search_path" to '' as $$
	select s.id, public.submission_has_editor(s.id)
	from public.submissions s
	where s.venue = _venue;
$$;

alter function public.venue_submission_editors (uuid) OWNER to "postgres";

revoke
execute on function public.venue_submission_editors (uuid)
from
	public;

grant
execute on function public.venue_submission_editors (uuid) to authenticated;

create or replace function public.isAssigned (_submissionid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER
set
	"search_path" to '' as $$
	select (exists (select id from public.assignments where submission=_submissionid and scholar=(select auth.uid()) and approved=true))
$$;

alter function public.isAssigned (_submissionid uuid) OWNER to "postgres";

grant all on FUNCTION public.isAssigned (_submissionid uuid) to "anon";

grant all on FUNCTION public.isAssigned (_submissionid uuid) to "authenticated";

grant all on FUNCTION public.isAssigned (_submissionid uuid) to "service_role";

-- True if the current scholar is an accepted volunteer on any role in the
-- approver chain ABOVE the given role (its approver, that role's approver, and
-- so on). These are the scholars empowered to make/oversee assignments to the
-- role, so they may see its assignments. Walks roles.approver upward with a
-- depth guard to tolerate accidental cycles.
create or replace function public.isInApproverChain (_roleid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER
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

alter function public.isInApproverChain (_roleid uuid) OWNER to "postgres";

grant all on FUNCTION public.isInApproverChain (_roleid uuid) to "anon";

grant all on FUNCTION public.isInApproverChain (_roleid uuid) to "authenticated";

grant all on FUNCTION public.isInApproverChain (_roleid uuid) to "service_role";

-- True if the current scholar has a declared conflict of interest on the given
-- submission. plpgsql (not sql) so the body's reference to public.conflicts is
-- resolved at run time, since the conflicts table loads after this file.
create or replace function public.isConflicted (_submissionid uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
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

alter function public.isConflicted (_submissionid uuid) OWNER to "postgres";

grant all on FUNCTION public.isConflicted (_submissionid uuid) to "anon";

grant all on FUNCTION public.isConflicted (_submissionid uuid) to "authenticated";

grant all on FUNCTION public.isConflicted (_submissionid uuid) to "service_role";

-- True if the current scholar is an author of the given submission. SECURITY
-- DEFINER so the assignments SELECT policy can read submissions.authors without
-- triggering the submissions RLS policy (which itself reads assignments — that
-- mutual reference would otherwise be infinite recursion).
create or replace function public.isAuthor (_submissionid uuid) returns boolean language sql security definer
set
	"search_path" to '' as $$
	select exists (
		select 1 from public.submissions
		where id = _submissionid and (select auth.uid()) = any (authors)
	);
$$;

alter function public.isAuthor (_submissionid uuid) OWNER to "postgres";

grant all on FUNCTION public.isAuthor (_submissionid uuid) to "anon";

grant all on FUNCTION public.isAuthor (_submissionid uuid) to "authenticated";

grant all on FUNCTION public.isAuthor (_submissionid uuid) to "service_role";

--------------------------------------
-- Security
alter table public.assignments enable row level security;

-- We declare the select policy for submissions after the assigments table is created.
create policy "admins, authors, assigned, and bidders can view submissions" on "public"."submissions" as permissive for
select
	to anon,
	authenticated using (
		public.isadmin (venue)
		or (
			(
				select
					auth.uid ()
			)=any (authors)
		)
		or exists (
			select
				volunteers.id
			from
				public.volunteers
			where
				volunteers.scholarid=(
					select
						auth.uid ()
				)
				and volunteers.accepted='accepted'::invited
				and volunteers.roleid=any (
					array(
						select
							roles.id
						from
							public.roles
						where
							roles.venueid=submissions.venue
							and roles.biddable=true
					)
				)
		)
		or exists (
			select
				assignments.id
			from
				public.assignments
			where
				assignments.submission=submissions.id
				and assignments.approved=true
				and assignments.scholar=(
					select
						auth.uid ()
				)
		)
		or exists (
			select
				assignments.id
			from
				public.assignments
			where
				assignments.submission=submissions.id
				and public.isRoleApproverVolunteer (assignments.role)
		)
		-- The venue's editors, whether or not they are venue admins and whether or not
		-- they are assigned to this submission yet. Every other branch above requires a
		-- foothold ON the submission, so a priority-0 volunteer who was not also an admin
		-- could not see an unassigned submission at all -- which made a submission
		-- waiting for an editor invisible to precisely the people meant to pick it up.
		-- Deliberately the more generous of the two editor rules: isPriorityZero asks only
		-- that the role be accepted, while can_claim_editor_role also requires the
		-- volunteer to be active, because seeing a venue's work is not the same as taking
		-- a piece of it on.
		or public.isPriorityZero (submissions.venue)
	);

-- We declare the submissions update policy after the assignments table is created
-- So we can refer to the assignments.
create policy "authors and editors can update submissions" on public.submissions
for update
	to authenticated using (
		-- The authenticated scholar has a top priority role on this submission
		(
			exists (
				select
					id
				from
					public.assignments
				where
					assignments.submission=submissions.id
					and scholar=(
						select
							auth.uid ()
					)
					and approved=true
					and exists (
						select
							id
						from
							public.roles
						where
							id=assignments.role
							and priority=0
					)
			)
		)
		-- The authenticated scholar is an author on this submission
		or (
			(
				select
					auth.uid ()
			)=any (authors)
		)
	);

-- Assignment visibility: the assigned scholar always sees their own assignment.
-- Otherwise, only the approver chain for the role (and venue admins) may see it,
-- and never if that viewer is conflicted on the submission.
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
			-- The approver chain for the role, or venue admins, may see it,
			-- unless they are conflicted on the submission.
			or (
				(
					public.isInApproverChain (role)
					or public.isAdmin (venue)
				)
				and not public.isConflicted (submission)
			)
			-- Open review: when the venue is not anonymous, the submission's
			-- authors may see who is assigned (unless they are conflicted).
			or (
				(
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

create policy "assignees and approvers can update assignments" on public.assignments
for update
	to authenticated using (
		(
			(
				scholar=(
					select
						auth.uid () as "uid"
				)
			)
			or public.isRoleApproverVolunteer (role)
		)
	);

create policy "assignees can delete assignments" on "public"."assignments" for delete to authenticated using (
	(
		scholar=(
			select
				auth.uid () as "uid"
		)
	)
);

create policy "admins, approvers and volunteers can create assignments" on "public"."assignments" for insert to "authenticated"
with
	check (
		(
			-- If the current scholar is an admin, they can create any assignment.
			public.isAdmin (venue)
			-- If the current scholar has an assigment to the role that is the approver for the new assignment's role.
			or (
				public.isRoleApproverVolunteer (role)
				and isAssigned (submission)
			)
			-- If the venue permits bidding and the volunteer has the role for which this assignment is being created.
			or (
				bid
				and (
					exists (
						select
						from
							public.volunteers
						where
							(
								(volunteers.roleid=assignments.role)
								and (
									volunteers.scholarid=(
										select
											auth.uid () as "uid"
									)
								)
								and volunteers.active
								and (volunteers.accepted='accepted')
							)
					)
				)
			)
			-- An editor of the venue claiming a submission nobody is editing yet. See
			-- public.can_claim_editor_role above for why this branch has to exist and
			-- why it is drawn this narrowly; the checks here are the ones the function
			-- cannot make for itself, since it is not told who is being seated.
			or (
				scholar=(
					select
						auth.uid () as "uid"
				)
				and not bid
				and not completed
				and public.can_claim_editor_role (submission, role)
			)
		)
	);

-- The submissions UPDATE policy lets authors edit their submission, but authors
-- must NOT be able to change the author list (authors/payments/transactions);
-- only a priority-0 assigned scholar on the paper may. RLS using-clauses cannot
-- be column-specific, so enforce the author-list lock with a BEFORE UPDATE
-- trigger (mirrors the revoke-update lock on submissions.status/completed_at).
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

create or replace trigger enforce_submission_author_edits
before update on public.submissions for each row
execute function public.enforce_submission_author_edits ();

grant all on table public.assignments to "anon";

grant all on table public.assignments to "authenticated";

grant all on table public.assignments to "service_role";

alter publication supabase_realtime
add table assignments;

--------------------------------------
-- RPC (authoritative definition from migration 20260804020000_token_event_attribution)
create or replace function public.complete_assignment (
	_assignment_id uuid,
	_payment_purpose_template text,
	_mint_purpose_template text
) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
    _caller uuid;
    _assignment public.assignments;
    _role public.roles;
    _venue public.venues;
    _submission public.submissions;
    _amount integer;
    _available integer;
    _token_ids uuid[];
    _txn_id uuid;
    _mint_txn_id uuid;
    _shortfall integer;
    _mint_purpose text;
    _payment_purpose text;
begin
    _caller := (select auth.uid());
    if _caller is null then
        raise exception 'Authentication required';
    end if;

    select * into _assignment from public.assignments where id = _assignment_id;
    if not found then
        raise exception 'Assignment not found';
    end if;
    if _assignment.completed then
        raise exception 'Assignment is already completed';
    end if;
    if not _assignment.approved then
        raise exception 'Assignment must be approved before it can be completed';
    end if;

    select * into _role from public.roles where id = _assignment.role;
    if not found then
        raise exception 'Role not found';
    end if;

    -- Authorize the caller against the single definition of the rule. The same
    -- three branches are asserted in TypeScript by canApproveAssignment.unit.ts
    -- and in SQL by atomic_crud_rpc.sql, over the same table of cases.
    if not public.can_approve_assignment(_assignment.submission, _assignment.role) then
        raise exception 'You are not authorized to compensate this assignment';
    end if;

    select * into _venue from public.venues where id = _assignment.venue;
    if not found then
        raise exception 'Venue not found';
    end if;

    select * into _submission from public.submissions where id = _assignment.submission;
    if not found then
        raise exception 'Submission not found';
    end if;

    select amount into _amount from public.compensation
        where role = _assignment.role and submission_type = _submission.submission_type;
    if _amount is null then
        raise exception 'No compensation amount is configured for this role and submission type';
    end if;

    -- Substitute named placeholders in the localized purpose template.
    -- Supported placeholders: {role}, {title}, {amount}, {shortfall}.
    _payment_purpose := replace(
        replace(_payment_purpose_template, '{role}', _role.name),
        '{title}', _submission.title
    );

    -- How many tokens does the venue actually hold in this currency?
    select count(*) into _available from public.tokens
        where venue = _assignment.venue and currency = _venue.currency;

    if _available < _amount then
        _shortfall := _amount - _available;
        _mint_purpose := replace(
            replace(
                replace(
                    replace(_mint_purpose_template, '{amount}', _amount::text),
                    '{role}', _role.name
                ),
                '{title}', _submission.title
            ),
            '{shortfall}', _shortfall::text
        );

        -- Record a proposed mint so the minter has a pre-explained item to
        -- approve in the venue transactions page.
        insert into public.transactions (
            creator, from_scholar, from_venue, to_scholar, to_venue,
            tokens, currency, purpose, status
        ) values (
            _caller, null, null, null, _assignment.venue,
            array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[_shortfall]),
            _venue.currency, _mint_purpose, 'proposed'
        ) returning id into _mint_txn_id;

        return jsonb_build_object(
            'status', 'insufficient',
            'shortfall', _shortfall,
            'amount', _amount,
            'mint_transaction_id', _mint_txn_id,
            'venue_id', _assignment.venue,
            'venue_title', _venue.title,
            'currency_id', _venue.currency,
            'scholar_id', _assignment.scholar,
            'submission_id', _assignment.submission,
            'role_name', _role.name
        );
    end if;

    -- Pick the tokens to move. Order is stable but arbitrary.
    select array_agg(id) into _token_ids from (
        select id from public.tokens
            where venue = _assignment.venue and currency = _venue.currency
            order by id
            limit _amount
    ) sub;

    -- Attribute the payout to its transaction. Generated up front: the tokens
    -- move before the transaction row exists, and the token_events trigger reads
    -- app.txn at the moment of the write.
    _txn_id := gen_random_uuid();
    perform set_config('app.txn', _txn_id::text, true);

    -- Reassign the tokens to the scholar.
    update public.tokens
        set venue = null, scholar = _assignment.scholar
        where id = any(_token_ids);

    -- Record the approved transaction.
    insert into public.transactions (
        id, creator, from_scholar, from_venue, to_scholar, to_venue,
        tokens, currency, purpose, status
    ) values (
        _txn_id, _caller, null, _assignment.venue, _assignment.scholar, null,
        _token_ids, _venue.currency, _payment_purpose, 'approved'
    );

    perform set_config('app.txn', '', true);

    -- Mark the assignment completed.
    update public.assignments set completed = true where id = _assignment_id;

    return jsonb_build_object(
        'status', 'transferred',
        'transaction_id', _txn_id,
        'amount', _amount,
        'role_name', _role.name,
        'venue_id', _assignment.venue,
        'scholar_id', _assignment.scholar,
        'submission_id', _assignment.submission
    );
end;
$function$;
