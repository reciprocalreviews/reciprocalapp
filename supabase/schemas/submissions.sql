/* SCHEMA  */
-- The status of a submission, in relation to payments.
create type public.submission_status as enum('reviewing', 'done');

alter type public.submission_status OWNER to "postgres";

create table submissions (
	-- The unique ID of the submission
	id uuid not null default gen_random_uuid() primary key,
	-- The venue to which the submission corresponds
	venue uuid not null references venues (id),
	-- The external unique identifier of the submission, such as a submission number or manuscript number
	externalid text not null,
	-- An optional free-text link to a previous external submission id, for a predecessor that is not (yet)
	-- on this platform. Retained for bulk import and the multi-year transition period.
	previousid text default null,
	-- An optional explicit foreign key to a previous submission on this platform (a resubmission chain).
	-- Null if there is no on-platform predecessor.
	previous uuid default null references submissions (id) on delete set null,
	-- The submission type of the paper
	submission_type uuid not null references submission_types (id),
	-- The scholars associated with the submission
	authors uuid[] not null check (cardinality(authors)>0),
	-- The token amounts proposed for the submission, corresponding to the authors
	payments integer[] not null check (cardinality(payments)=cardinality(authors)),
	-- The transactions corresponding to the payments, corresponding to the authors. Null uuid of not yet paid.
	transactions uuid[] not null check (cardinality(transactions)=cardinality(authors)),
	-- An optional title for public bidding
	title text not null default ''::text,
	-- An optional description of expertise required for public bidding
	expertise text default null,
	-- The status of the submission in relation to payments.
	status submission_status not null default 'reviewing',
	-- When the submission was marked done (null while still under review).
	-- Set by the mark_submission_done RPC; cannot be reverted.
	completed_at timestamp with time zone default null
);

alter table public.submissions OWNER to "postgres";

grant all on table public.submissions to "anon";

grant all on table public.submissions to "authenticated";

grant all on table public.submissions to "service_role";

-- Lock the completion state (status, completed_at) from direct UPDATEs: only the
-- mark_submission_done RPC (SECURITY DEFINER) may write them. A column-level
-- revoke is ineffective while authenticated holds the TABLE-level UPDATE granted
-- by `grant all` above, so remove the table-level UPDATE and re-grant only the
-- editable columns. (The author list among these is further gated to priority-0
-- assigned scholars by the enforce_submission_author_edits trigger.)
revoke update on public.submissions from authenticated;

grant update (
	venue, externalid, previousid, previous, submission_type, authors, payments, transactions, title, expertise
) on public.submissions to authenticated;

--------------------------------------
-- Indexes
create index submissions_externalid_index on public.submissions using btree (externalid);

create index submissions_previous_index on public.submissions using btree (previous);

create index submissions_scholar_index on public.submissions using btree (authors);

create index submissions_venue_index on public.submissions using btree (venue);

--------------------------------------
-- Security
alter table public.submissions ENABLE row LEVEL SECURITY;

-- Select policy is in assignments.sql, after assignments table is declared.
create policy "anyone can create submissions" on public.submissions for INSERT to authenticated
with
	check (true);

create policy "admins can delete submissions" on public.submissions for DELETE to authenticated using (public.isAdmin (venue));

--------------------------------------
-- RPCs (defined in migration 20260608000000_atomic_crud.sql)
-- create_submission: create the proposed payment transactions for each paying
-- author, immediately approve the submitter's own charge (moving their tokens to
-- the venue), and insert the submission with aligned authors/payments/
-- transactions arrays — all atomically, so a partial failure can't orphan
-- proposed transactions or violate the array-cardinality CHECK constraints.
-- Author resolution and balance pre-checks (reads) stay in the application
-- layer; this function receives already-resolved author ids and charges.
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
	search_path = public, pg_temp as $function$
declare
	_caller uuid;
	_currency uuid;
	_transactions uuid[] := array[]::uuid[];
	_i integer;
	_author uuid;
	_payment integer;
	_txn_id uuid;
	_token_ids uuid[];
	_submission_id uuid;
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

	-- Return the new submission id.
	return jsonb_build_object('submission_id', _submission_id);
end;
$function$;

revoke execute on function public.create_submission (uuid, text, text, uuid, uuid, uuid[], integer[], text, text, text, text) from public;
grant execute on function public.create_submission (uuid, text, text, uuid, uuid, uuid[], integer[], text, text, text, text) to authenticated;

alter publication supabase_realtime
add table submissions;
