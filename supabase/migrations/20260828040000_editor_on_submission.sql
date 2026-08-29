-- A submission used to arrive and reach nobody.
--
-- create_submission wrote transaction rows and the submission row and no assignments,
-- the only mail went to co-authors who owed money, and the daily reminder job's one
-- submission family skips a submission with no editor because it has no recipient. An
-- editor learned a paper had arrived by remembering to look at the list.
--
-- Two things follow from the fact that a priority-0 assignment is also a payment
-- commitment -- mark_submission_done pays every approved priority-0 assignment on the
-- submission:
--
--   1. A submission can only be auto-assigned when the choice is unambiguous. Seating
--      every editor would multiply the editor payout per paper and could push the venue
--      into the insufficient-reserve path that records a proposed mint.
--   2. The venue's editors need to be able to seat THEMSELVES, which until now only a
--      venue admin could do -- so a notice saying "this needs an editor" would have gone
--      to people with no way to act on it.
--
-- Two more things turned up on the way, both the same shape: every branch of the
-- submissions SELECT policy required a foothold ON the submission, so a venue editor who
-- was not also an admin could not SEE an unassigned submission; and the assignments
-- policy tells them nothing either, so they could not tell which submissions already had
-- an editor. The first is fixed by widening the submissions policy. The second is
-- answered with a boolean rather than by widening the assignments policy, because
-- reviewer identities are a high price for a yes/no question.

--------------------------------------
-- 1. Let a venue's editors see their venue's submissions.
drop policy if exists "admins, authors, assigned, and bidders can view submissions" on public.submissions;

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

--------------------------------------
-- 2. Tell them which submissions already have an editor, without naming anyone.
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

--------------------------------------
-- 3. Let a venue's editors claim a submission nobody is editing yet.
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

--------------------------------------
-- 4. Add that branch to the assignments INSERT policy.
drop policy if exists "admins, approvers and volunteers can create assignments" on public.assignments;

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

--------------------------------------
-- 5. create_submission seats the venue's sole editor, and reports who (if anyone).
create or replace function public.create_submission (
	_venue uuid,
	_external_id text,
	_previous_id text,
	_previous uuid,
	_submission_type uuid,
	_authors uuid[],
	_payments integer[],
	_title text,
	_expertise text,
	_note text,
	_purpose text
) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_currency uuid;
	_cost integer;
	_transactions uuid[] := array[]::uuid[];
	_i integer;
	_author uuid;
	_payment integer;
	_txn_id uuid;
	_token_ids uuid[];
	_submission_id uuid;
	_editor_role uuid;
	_editors uuid[];
	_editor uuid;
begin
	-- Identify and require an authenticated caller (the submitter).
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	-- Every author must have a corresponding payment, and there must be one.
	if cardinality(_authors) <> cardinality(_payments) then
		raise exception 'Authors and payments must align';
	end if;
	if cardinality(_authors) = 0 then
		raise exception 'A submission needs at least one author';
	end if;

	-- Only a listed author may create a submission, unless the caller is a venue
	-- admin adding one manually. RR009 surfaces the specific message.
	if not (_caller = any(_authors) or public.isadmin(_venue)) then
		raise exception 'Only a listed author or a venue admin can create a submission'
			using errcode = 'RR009';
	end if;

	-- No author may be listed twice. The loop below indexes _authors positionally,
	-- so a repeat would be charged twice for one manuscript.
	if cardinality(_authors) <> (select count(distinct a) from unnest(_authors) a) then
		raise exception 'A submission cannot list the same author more than once'
			using errcode = 'RR008';
	end if;

	-- The type must belong to this venue, and the charges must add up to its cost.
	select submission_cost into _cost
	from public.submission_types
	where id = _submission_type and venue = _venue;
	if _cost is null then
		raise exception 'Submission type not found for this venue';
	end if;
	-- sum() ignores NULLs and returns NULL over an empty set; the loop below reads
	-- a NULL payment as 0, so coalesce here to agree with it. Payment-free venues
	-- have zero-cost types and zero payments, so this holds as 0 = 0.
	if coalesce((select sum(p) from unnest(_payments) p), 0) <> _cost then
		raise exception 'Author payments must add up to the submission cost of %', _cost
			using errcode = 'RR007';
	end if;

	-- Charges are denominated in the venue's currency.
	select currency into _currency from public.venues where id = _venue;
	if _currency is null then
		raise exception 'Venue not found';
	end if;

	-- Build the parallel transactions[] array, one entry per author.
	for _i in 1 .. cardinality(_authors) loop
		_author := _authors[_i];
		_payment := _payments[_i];

		-- A non-paying co-author (zero charge) gets a placeholder, not a
		-- transaction — there is nothing to collect from them.
		if coalesce(_payment, 0) = 0 then
			_transactions := _transactions || '00000000-0000-0000-0000-000000000000'::uuid;
			continue;
		end if;

		-- Record this author's charge as a proposed scholar->venue payment.
		insert into public.transactions (
			creator, from_scholar, from_venue, to_scholar, to_venue,
			tokens, currency, purpose, status
		) values (
			_caller, _author, null, null, _venue,
			array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[_payment]),
			_currency, _purpose, 'proposed'
		) returning id into _txn_id;

		-- Attribute this author's token movement to this author's charge. Set inside
		-- the loop, not once for the function: each author is a separate transaction,
		-- and one GUC for the whole call would file every movement under the last id.
		perform set_config('app.txn', _txn_id::text, true);

		-- The submitter's own charge is settled now: move their tokens to the
		-- venue and approve the transaction. Co-authors approve theirs later.
		if _author = _caller then
			-- Take exactly _payment of the submitter's tokens in this currency.
			select array_agg(id) into _token_ids
			from (
				select id from public.tokens
				where currency = _currency and scholar = _caller
				order by id limit _payment
			) sub;
			-- Can't pay? Abort the whole submission (everything rolls back). RR003
			-- surfaces the specific "insufficient tokens" message.
			if _token_ids is null or cardinality(_token_ids) < _payment then
				raise exception 'You do not have enough tokens to pay your submission charge' using errcode = 'RR003';
			end if;
			update public.tokens set scholar = null, venue = _venue where id = any(_token_ids);
			update public.transactions set status = 'approved', tokens = _token_ids where id = _txn_id;
		end if;

		perform set_config('app.txn', '', true);

		_transactions := _transactions || _txn_id;
	end loop;

	-- Insert the submission with the three aligned arrays. The equal-cardinality
	-- CHECK constraints hold because we appended exactly one entry per author.
	insert into public.submissions (
		venue, externalid, previousid, previous, submission_type,
		authors, payments, transactions, title, expertise, note
	) values (
		_venue, _external_id, _previous_id, _previous, _submission_type,
		_authors, _payments, _transactions, coalesce(_title, ''), _expertise, _note
	) returning id into _submission_id;

	-- Seat the venue's editor, when there is exactly one it could be.
	--
	-- A priority-0 assignment is also a compensation commitment: mark_submission_done
	-- pays every approved priority-0 assignment on the submission. So this only fires
	-- when the choice is unambiguous. Several eligible editors would mean an arbitrary
	-- pick, and seating them all would mean several editor fees per paper; a sole editor
	-- who is an author here would be editing their own submission. In any of those cases
	-- nobody is seated, and the caller notifies the candidates instead.
	select r.id into _editor_role
	from public.roles r
	where r.venueid = _venue and r.priority = 0
	order by r.id
	limit 1;

	if _editor_role is not null then
		select array_agg(v.scholarid) into _editors
		from public.volunteers v
		where v.roleid = _editor_role and v.active and v.accepted = 'accepted';

		if cardinality(coalesce(_editors, array[]::uuid[])) = 1
			and not (_editors[1] = any(_authors)) then
			_editor := _editors[1];
			insert into public.assignments (venue, submission, scholar, role, bid, approved)
			values (_venue, _submission_id, _editor, _editor_role, false, true);
		end if;
	end if;

	-- Return the new submission id, and who is editing it. A null editor is the
	-- caller's cue to send the "this submission needs an editor" notice instead of
	-- the "you were assigned one" notice.
	return jsonb_build_object('submission_id', _submission_id, 'editor', _editor);
end;
$function$;

--------------------------------------
-- 6. bulk_import_submissions does the same, per imported row.
create or replace function public.bulk_import_submissions (
	_venueid uuid,
	_submissions jsonb,
	_import_note text
) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
    _admin_id uuid;
    _currency uuid;
    _count integer;
    _mint_amount integer;
    _submission_ids uuid[];
    _new_submission_id uuid;
    _transaction_id uuid;
    _row jsonb;
    _previousid text;
    _previous uuid;
    _type_cost integer;
    _tokens uuid[];
    _editor_role uuid;
    _editors uuid[];
    _editor uuid;
    _seated integer := 0;
begin
    _admin_id := (select auth.uid());

    if _admin_id is null then
        raise exception 'Authentication required';
    end if;

    if not public.isadmin(_venueid) then
        raise exception 'Only venue admins can bulk import submissions';
    end if;

    select currency into _currency
    from public.venues
    where id = _venueid;

    if _currency is null then
        raise exception 'Venue not found';
    end if;

    _count := jsonb_array_length(_submissions);
    if _count = 0 then
        raise exception 'No submissions provided';
    end if;

    _mint_amount := 0;

    -- Resolve the venue's sole editor once, on the same unambiguous-only rule as
    -- create_submission. Imported rows carry no authors, so the "not an author of this
    -- paper" half of that rule has nothing to test here.
    select r.id into _editor_role
    from public.roles r
    where r.venueid = _venueid and r.priority = 0
    order by r.id
    limit 1;

    if _editor_role is not null then
        select array_agg(v.scholarid) into _editors
        from public.volunteers v
        where v.roleid = _editor_role and v.active and v.accepted = 'accepted';

        if cardinality(coalesce(_editors, array[]::uuid[])) = 1 then
            _editor := _editors[1];
        end if;
    end if;

    _submission_ids := array[]::uuid[];
    for _row in select * from jsonb_array_elements(_submissions)
    loop
        _previousid := nullif(_row->>'previousid', '');

        -- Best-effort resolve the free-text predecessor to an on-platform
        -- submission in this venue. Unresolved (off-platform) predecessors
        -- keep previousid only, with previous left null.
        _previous := null;
        if _previousid is not null then
            select id into _previous
            from public.submissions
            where venue = _venueid and externalid = _previousid
            limit 1;
        end if;

        insert into public.submissions (
            venue,
            externalid,
            previousid,
            previous,
            authors,
            payments,
            transactions,
            title,
            expertise,
            submission_type,
            note,
            imported
        ) values (
            _venueid,
            _row->>'externalid',
            _previousid,
            _previous,
            array[]::uuid[],
            array[]::integer[],
            array[]::uuid[],
            coalesce(_row->>'title', ''),
            nullif(_row->>'expertise', ''),
            (_row->>'submission_type')::uuid,
            nullif(_row->>'note', ''),
            true
        ) returning id into _new_submission_id;
        _submission_ids := _submission_ids || _new_submission_id;

        if _editor is not null then
            insert into public.assignments (venue, submission, scholar, role, bid, approved)
            values (_venueid, _new_submission_id, _editor, _editor_role, false, true);
            _seated := _seated + 1;
        end if;

        -- Each row bills its submission type's cost.
        select submission_cost into _type_cost
        from public.submission_types
        where id = (_row->>'submission_type')::uuid;
        _mint_amount := _mint_amount + coalesce(_type_cost, 0);
    end loop;

    if _mint_amount > 0 then
        _tokens := array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[_mint_amount]);

        insert into public.transactions (
            creator,
            from_scholar,
            from_venue,
            to_scholar,
            to_venue,
            tokens,
            currency,
            purpose,
            status
        ) values (
            _admin_id,
            null,
            null,
            null,
            _venueid,
            _tokens,
            _currency,
            coalesce(nullif(_import_note, ''), 'Mint to fund imported pre-launch submissions'),
            'proposed'
        ) returning id into _transaction_id;
    end if;

    return jsonb_build_object(
        'submission_ids', to_jsonb(_submission_ids),
        'transaction_id', _transaction_id,
        'mint_amount', _mint_amount,
        'editor', _editor,
        'seated', _seated
    );
end;
$function$;
