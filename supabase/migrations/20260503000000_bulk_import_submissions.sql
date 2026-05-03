-- Support bulk import of pre-launch submissions: free submissions with no
-- authors or payments, accompanied by a single proposed mint transaction
-- that a minter must approve to fund reviewer compensation.

-- 1. Add imported and note columns to submissions.
alter table "public"."submissions"
add column "imported" boolean not null default false;

alter table "public"."submissions"
add column "note" text default null;

-- 2. Allow empty author lists for imported submissions. The original check
-- required at least one author; the new check exempts imported submissions.
alter table "public"."submissions"
drop constraint "submissions_authors_check";

alter table "public"."submissions"
add constraint "submissions_authors_check"
check (imported or cardinality(authors) > 0) not valid;

alter table "public"."submissions"
validate constraint "submissions_authors_check";

-- 3. Mirror the same allowance for payments and transactions. The existing
-- equality checks (cardinality(payments) = cardinality(authors), same for
-- transactions) remain in force and naturally permit empty arrays when
-- authors is empty.
alter table "public"."submissions"
add constraint "submissions_payments_nonempty_check"
check (imported or cardinality(payments) > 0) not valid;

alter table "public"."submissions"
validate constraint "submissions_payments_nonempty_check";

alter table "public"."submissions"
add constraint "submissions_transactions_nonempty_check"
check (imported or cardinality(transactions) > 0) not valid;

alter table "public"."submissions"
validate constraint "submissions_transactions_nonempty_check";

-- 4. Enforce externalid uniqueness within a venue. Replaces the prior
-- non-unique lookup index.
drop index if exists "public"."submissions_externalid_index";

create unique index "submissions_venue_externalid_unique"
on public.submissions(venue, externalid);

-- 5. Tighten the insert policy: non-imported submissions remain open
-- (the application layer enforces author/payment validity), but imported
-- submissions can only be inserted by venue admins.
drop policy "anyone can create submissions" on "public"."submissions";

create policy "anyone can create submissions, admins for imports"
on "public"."submissions" as permissive for insert to authenticated
with check (
    (not imported) or public.isadmin(venue)
);

-- Extend the SELECT policy so admins can view all submissions in their
-- venue. Without this, imported submissions (which have no authors and
-- no assigned reviewers yet) would be invisible to the very admin who
-- imported them.
drop policy "authors, assigned, and bidders can view submissions" on "public"."submissions";

create policy "admins, authors, assigned, and bidders can view submissions"
on "public"."submissions" as permissive for select to anon, authenticated
using (
    public.isadmin(venue)
    or ((select auth.uid()) = any(authors))
    or exists (
        select volunteers.id
        from public.volunteers
        where volunteers.scholarid = (select auth.uid())
            and volunteers.accepted = 'accepted'::invited
            and volunteers.roleid = any(
                array(select roles.id from public.roles where roles.venueid = submissions.venue and roles.biddable = true)
            )
    )
    or exists (
        select assignments.id
        from public.assignments
        where assignments.submission = submissions.id
            and assignments.approved = true
            and assignments.scholar = (select auth.uid())
    )
);

-- 6. Bulk import RPC. Atomically inserts a batch of imported submissions
-- and a single proposed mint transaction sized at submission_cost * N.
-- The minter approves the transaction separately to fund reviewer
-- compensation. Runs as SECURITY DEFINER and gates entry on isadmin —
-- inserts from inside a SECURITY INVOKER function don't reliably pass
-- RLS even when the caller is an admin, so we elevate and check
-- explicitly. The auth.uid() lookup still reflects the calling user
-- because the JWT GUC propagates regardless of definer/invoker mode.
create or replace function public.bulk_import_submissions(
    _venueid uuid,
    _submissions jsonb,
    _import_note text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    _admin_id uuid;
    _submission_cost integer;
    _currency uuid;
    _count integer;
    _mint_amount integer;
    _submission_ids uuid[];
    _new_submission_id uuid;
    _transaction_id uuid;
    _row jsonb;
    _tokens uuid[];
begin
    _admin_id := (select auth.uid());

    if _admin_id is null then
        raise exception 'Authentication required';
    end if;

    if not public.isadmin(_venueid) then
        raise exception 'Only venue admins can bulk import submissions';
    end if;

    select submission_cost, currency
    into _submission_cost, _currency
    from public.venues
    where id = _venueid;

    if _submission_cost is null then
        raise exception 'Venue not found';
    end if;

    _count := jsonb_array_length(_submissions);
    if _count = 0 then
        raise exception 'No submissions provided';
    end if;

    _mint_amount := _submission_cost * _count;

    _submission_ids := array[]::uuid[];
    for _row in select * from jsonb_array_elements(_submissions)
    loop
        insert into public.submissions (
            venue,
            externalid,
            previousid,
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
            nullif(_row->>'previousid', ''),
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
        'mint_amount', _mint_amount
    );
end;
$function$;

revoke execute on function public.bulk_import_submissions(uuid, jsonb, text) from public;
grant execute on function public.bulk_import_submissions(uuid, jsonb, text) to authenticated;
