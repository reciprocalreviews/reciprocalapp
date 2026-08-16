-- Give the "who may approve an assignment" rule ONE definition, and stop a
-- different rule from impersonating it.
--
-- The rule was written out four times: canApproveAssignment.ts (UI gating), the
-- authorization block inside complete_assignment (the enforcing copy, whose comment
-- said "Mirrors canApproveAssignment.ts"), a hand-rolled variant inside
-- SupabaseCRUD.requestCompensation that picked email recipients, and — apparently —
-- public.isApprover. Three of those really were the same rule and have been
-- reconciled. The fourth never was, and that is the more dangerous half of this
-- change, so it is worth being precise about.
--
-- TWO RULES, NOT ONE
--
-- public.isApprover(role) asks: is the caller an ACCEPTED VOLUNTEER on the role that
-- approves this one, anywhere in the venue? It reads public.volunteers, takes no
-- submission, and has no admin or editor branch.
--
-- can_approve_assignment(submission, role) asks: does the caller hold an APPROVED
-- ASSIGNMENT on THIS submission, either for the venue's priority-0 role or for the
-- role that approves this one — or are they a venue admin?
--
-- Those are different questions with different answers in both directions. A scholar
-- who accepted an approver role but was never assigned to a submission satisfies the
-- first and not the second; a venue admin satisfies the second and not the first.
--
-- WHY isApprover IS RENAMED RATHER THAN CHANGED
--
-- It is tempting to "fix" isApprover into agreement. It must not be: it is the USING
-- clause of the assignments UPDATE policy, which has no admin branch and no
-- submission scoping. Narrowing it to require an approved assignment on the
-- submission would silently revoke UPDATE from every accepted volunteer who approves
-- a role without holding an assignment on the row they are approving — which is the
-- ordinary case for an AE approving a reviewer's bid. That is a permissions change,
-- not a refactor, and it would quietly break bidding.
--
-- So the rule keeps its behaviour and loses its misleading name. isApprover becomes
-- isRoleApproverVolunteer, which says what it actually tests. The three policies that
-- use it are recreated against the new name; nothing about who can do what changes.
--------------------------------------
-- The approval rule, defined once.
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

--------------------------------------
-- The venue-wide volunteer test, renamed to stop it reading as the rule above.
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

--------------------------------------
-- Recreate the three policies that referenced the old name. The predicates are
-- unchanged; only the function they call is renamed.
drop policy if exists "admins, authors, assigned, and bidders can view submissions" on public.submissions;

create policy "admins, authors, assigned, and bidders can view submissions" on public.submissions as permissive for
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
	);

drop policy if exists "assignees and approvers can update assignments" on public.assignments;

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

drop policy if exists "admins, approvers and volunteers can create assignments" on public.assignments;

create policy "admins, approvers and volunteers can create assignments" on public.assignments for insert to authenticated
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
		)
	);

--------------------------------------
-- Point the enforcing copy at the shared definition. Without this the rule would
-- exist in two places again the moment it was extracted — the function above and
-- the block that used to be inlined here.
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

drop function if exists public.isApprover (uuid);
