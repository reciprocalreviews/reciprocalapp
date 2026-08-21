-- Enforce two submission rules in the database that only the client enforced.
--
-- DESIGN.md states that a submission's charges add up to its type's cost, and the
-- new-submission form refuses to submit when they don't. `create_submission` never
-- read `submission_types.submission_cost` at all, so the rule held only for callers
-- who came through that form. Anything reaching the RPC directly — a script, a
-- future CLI, a bug in the form's own arithmetic — could name its own price and the
-- database would record it without complaint. The same was true of a duplicated
-- author: the client showed a warning about it but never blocked submission, and the
-- RPC's loop indexes `_authors` positionally, so the same person listed twice got two
-- proposed charges, and if they were also the submitter, two settled payments for one
-- manuscript.
--
-- WHY THESE ARE RAISED, NOT CONSTRAINED
--
-- Neither rule can be a CHECK constraint. The cost rule spans two tables
-- (submissions.payments against submission_types.submission_cost), and the
-- duplicate-author rule would need to hold only for new rows — bulk-imported
-- submissions come in through a different path with no payments at all. Both belong
-- where the write is already gated, which is this function.
--
-- A THIRD CHECK, WHILE WE ARE HERE
--
-- `_submission_type` was accepted and never validated: it was passed straight into
-- the INSERT, so a submission could be filed under a type belonging to a different
-- venue. The cost lookup added below has to name the venue anyway to be meaningful,
-- so the check comes for free rather than as scope creep.
--
-- RR007 = payments do not sum to the type's cost.
-- RR008 = the same author is listed more than once.
-- Both are user-actionable, hence RR codes rather than a bare raise (see
-- ARCHITECTURE.md's RR-code table).
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

	-- Return the new submission id.
	return jsonb_build_object('submission_id', _submission_id);
end;
$function$;
