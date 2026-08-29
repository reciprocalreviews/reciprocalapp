-- Let a venue admin mint the venue's currency, and disclose it instead of forbidding it.
--
-- WHY
--
-- 20260828000010 narrowed the admin/minter separation to a launch gate: the overlap was
-- tolerated while a venue was `inactive` and refused the moment it went live. That is still
-- too strict. It stops a venue going live at exactly the point a community is trying to
-- join the platform, it cannot describe a small community where one person is the whole
-- organization, and it treats every organizer as a suspect before they have done anything.
--
-- So the rule stops being a prohibition and becomes a disclosure. The overlap is legal at
-- every layer; the venue page shows a prominent notice to everyone who is neither an admin
-- of the venue nor a minter of its currency, naming the arrangement and inviting them to
-- take the minting role over. Oversight comes from the community seeing the arrangement,
-- not from the database refusing to represent it.
--
-- Three layers come down:
--
--   1. The mirrored triggers `no_minter_admins` (venues) and `no_admin_minters`
--      (currencies), and the RR015 errcode they shared. Nothing maps RR015 in the client.
--   2. `mint_tokens`' refusal to mint into a venue the caller administers. Keeping it would
--      have made the relaxation hollow: a solo admin-minter could hold both roles and still
--      never put a token in their own venue's reserve.
--   3. `approve_transaction`'s RR002 refusal, but only for **pure mints** — a transaction
--      with no source. Approving a mint into a venue you administer is the same act as
--      minting into it directly, so the two must agree.
--
-- What deliberately stays: approving a *transfer* into a venue you administer, and
-- `transfer_tokens`' matching refusal. Those move tokens that already exist and belong to
-- someone else, which is a different act from creating new ones, and no small-community
-- argument requires them. The `transactions` INSERT policy also still refuses a directly
-- inserted approved mint into a venue you administer; every mint in the app goes through
-- the SECURITY DEFINER RPCs above, which bypass it, so relaxing that policy would widen
-- the hand-written-PostgREST surface for no gain.
--------------------------------------
-- 1. The structural prohibition
--------------------------------------
drop trigger if exists no_minter_admins on public.venues;

drop function if exists public.no_minter_admins ();

drop trigger if exists no_admin_minters on public.currencies;

drop function if exists public.no_admin_minters ();

--------------------------------------
-- 2. mint_tokens: minting into a venue you administer
--------------------------------------
create or replace function public.mint_tokens (
	_currency uuid,
	_amount integer,
	_to_venue uuid,
	_purpose text
) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_token_ids uuid[];
	_txn_id uuid;
begin
	-- Identify and require an authenticated caller.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	-- A mint must create a positive number of tokens.
	if _amount is null or _amount <= 0 then
		raise exception 'Mint amount must be positive';
	end if;
	-- Only a minter of this currency may create its tokens (tokens INSERT policy).
	if not public.isminter(_caller, _currency) then
		raise exception 'Only currency minters can mint tokens';
	end if;

	-- Attribute the mint to the transaction it belongs to. The id is generated up
	-- front because the tokens are written before the transaction row exists, and
	-- the token_events trigger reads app.txn at the moment of the write.
	_txn_id := gen_random_uuid();
	perform set_config('app.txn', _txn_id::text, true);

	-- Create the tokens, owned by the destination venue, and capture their ids.
	with inserted as (
		insert into public.tokens (currency, venue, scholar)
		select _currency, _to_venue, null from generate_series(1, _amount)
		returning id
	)
	select array_agg(id) into _token_ids from inserted;

	-- Record the matching approved mint transaction (no source, to the venue).
	insert into public.transactions (
		id, creator, from_scholar, from_venue, to_scholar, to_venue,
		tokens, currency, purpose, status
	) values (
		_txn_id, _caller, null, null, null, _to_venue,
		_token_ids, _currency, _purpose, 'approved'
	);

	-- Clear it, so a later token write in this same database transaction that is
	-- NOT part of this mint is recorded as unattributed rather than borrowing this
	-- transaction's id. That is what keeps "txn is null" a trustworthy alarm.
	perform set_config('app.txn', '', true);

	-- Hand the new token ids and transaction id back to the caller.
	return jsonb_build_object('token_ids', to_jsonb(_token_ids), 'transaction_id', _txn_id);
end;
$function$;

--------------------------------------
-- 3. approve_transaction: approving a pure mint into a venue you administer
--------------------------------------
create or replace function public.approve_transaction (_transaction_id uuid) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_txn public.transactions;
	_from uuid;
	_to uuid;
	_spending_own boolean;
	_null_count integer;
	_needed integer;
	_token_ids uuid[];
begin
	-- Identify and require an authenticated caller.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- Load the transaction; it must exist and still be awaiting approval.
	select * into _txn from public.transactions where id = _transaction_id;
	if not found then
		raise exception 'Transaction not found';
	end if;
	-- RR001 lets the app show the specific "already approved" message.
	if _txn.status <> 'proposed' then
		raise exception 'Transaction is not proposed' using errcode = 'RR001';
	end if;

	-- Every token write below — the pure mint, the shortfall mint, and the
	-- transfer — belongs to this one transaction, so attribute once here. Cleared
	-- before each return so a later write in the same database transaction cannot
	-- inherit it.
	perform set_config('app.txn', _transaction_id::text, true);

	-- Collapse the from/to scholar-or-venue pairs into single endpoints; every
	-- transaction has a recipient.
	_from := coalesce(_txn.from_scholar, _txn.from_venue);
	_to := coalesce(_txn.to_scholar, _txn.to_venue);
	if _to is null then
		raise exception 'Transaction has no recipient';
	end if;

	-- No-self-enrichment: spending one's own balance is unrestricted; otherwise
	-- the approver may not be the recipient or an admin of the recipient venue.
	-- RR002 lets the app show the specific self-dealing message.
	--
	-- A pure mint (`_from` is null) into a venue you administer is exempt: a small
	-- community's organizer may be its only minter, and the platform now discloses
	-- that arrangement on the venue page rather than forbidding it. Moving tokens
	-- that already exist into a venue you run is a different act and still refused.
	_spending_own := (_txn.from_scholar is not null and _txn.from_scholar = _caller);
	if not _spending_own then
		if _txn.to_scholar is not null and _txn.to_scholar = _caller then
			raise exception 'You cannot approve a transaction that pays you' using errcode = 'RR002';
		end if;
		if _from is not null and _txn.to_venue is not null and public.isAdmin(_txn.to_venue) then
			raise exception 'You cannot approve a transaction that pays a venue you administer' using errcode = 'RR002';
		end if;
	end if;

	-- How many of the listed tokens are placeholders (not yet real tokens)?
	_null_count := (
		select count(*) from unnest(_txn.tokens) t
		where t = '00000000-0000-0000-0000-000000000000'::uuid
	);

	-- Branch A: pure mint — no source, all placeholders, a venue recipient.
	if _from is null then
		if _txn.to_venue is null then
			raise exception 'A mint transaction must target a venue';
		end if;
		if _null_count = 0 or _null_count <> cardinality(_txn.tokens) then
			raise exception 'A mint transaction must contain only placeholder tokens';
		end if;
		-- Only a minter may bring new tokens into existence.
		if not public.isminter(_caller, _txn.currency) then
			raise exception 'Only currency minters can approve a mint';
		end if;
		-- Mint the tokens straight into the recipient venue and capture their ids.
		with inserted as (
			insert into public.tokens (currency, venue, scholar)
			select _txn.currency, _txn.to_venue, null from generate_series(1, _null_count)
			returning id
		)
		select array_agg(id) into _token_ids from inserted;

		-- Finalize the transaction with the real token ids.
		update public.transactions set status = 'approved', tokens = _token_ids where id = _transaction_id;
		perform set_config('app.txn', '', true);
		return jsonb_build_object('transaction_id', _transaction_id, 'token_ids', to_jsonb(_token_ids));
	end if;

	-- Branch B: transfer. Authorize moving the source's tokens.
	if _txn.from_scholar is not null then
		-- A scholar's own balance: only that scholar may approve the spend.
		if _caller <> _txn.from_scholar then
			raise exception 'You can only approve transfers of your own tokens';
		end if;
	else
		-- A venue's reserve: a venue admin or a currency minter may approve
		-- (mirrors the transactions UPDATE policy).
		if not (public.isAdmin(_txn.from_venue) or public.isminter(_caller, _txn.currency)) then
			raise exception 'You are not authorized to approve this transaction';
		end if;
	end if;

	-- If the venue source is short real tokens, mint the placeholders into its
	-- reserve first. Minting requires a minter (tokens INSERT policy).
	if _null_count > 0 and _txn.from_venue is not null then
		if not public.isminter(_caller, _txn.currency) then
			raise exception 'Only currency minters can mint the tokens this transaction requires';
		end if;
		insert into public.tokens (currency, venue, scholar)
		select _txn.currency, _txn.from_venue, null from generate_series(1, _null_count);
	end if;

	-- Choose as many of the source's tokens as the transaction calls for.
	_needed := cardinality(_txn.tokens);
	select array_agg(id) into _token_ids
	from (
		select id from public.tokens
		where currency = _txn.currency
		  and (
			(_txn.from_scholar is not null and scholar = _txn.from_scholar)
			or (_txn.from_venue is not null and venue = _txn.from_venue)
		  )
		order by id
		limit _needed
	) sub;

	-- Bail (rolling back any mint above) if the source can't cover the transfer.
	if _token_ids is null or cardinality(_token_ids) < _needed then
		raise exception 'Insufficient tokens to complete the transfer' using errcode = 'RR003';
	end if;

	-- Move the tokens to the recipient and finalize the transaction together.
	update public.tokens set scholar = _txn.to_scholar, venue = _txn.to_venue where id = any(_token_ids);
	update public.transactions set status = 'approved', tokens = _token_ids where id = _transaction_id;

	perform set_config('app.txn', '', true);
	return jsonb_build_object('transaction_id', _transaction_id, 'token_ids', to_jsonb(_token_ids));
end;
$function$;

--------------------------------------
-- 4. approve_venue_proposal: its in-body comment described the old rule
--------------------------------------
-- Nothing about what this function does changes. The comment explaining why a steward may
-- hold the currency of a venue they administer said the overlap was "tolerated only while
-- the venue is inactive" — which is no longer true — and function comments live in prosrc,
-- so correcting one means replacing the function. CI diffs supabase/schemas against
-- supabase/migrations and fails on any difference, this one included.
create or replace function public.approve_venue_proposal (_proposal_id uuid) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_proposal public.proposals;
	_editor_ids uuid[];
	_minter_ids uuid[];
	_currency uuid;
	_venue uuid;
	_role uuid;
	_submission_type uuid;
	_editor uuid;
	_supporter_ids uuid[];
begin
	-- Only an authenticated steward may approve a proposal.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	if not public.isSteward() then
		raise exception 'Only stewards can approve venue proposals';
	end if;

	-- Load the proposal being approved.
	select * into _proposal from public.proposals where id = _proposal_id;
	if not found then
		raise exception 'Proposal not found';
	end if;

	-- Resolve the proposed editor emails to scholar ids, taking whoever has an account
	-- rather than demanding all of them. An editor who has not signed up yet was emailed an
	-- invitation when the proposal was filed and can be added later; requiring them up front
	-- would mean that invitation could only ever reach people who did not need it. At least
	-- one is a hard floor: venues_admins_check forbids a venue with no admins.
	select array_agg(id) into _editor_ids from public.scholars where email = any(_proposal.editors);
	if _editor_ids is null then
		raise exception 'No proposed editors have accounts' using errcode = 'RR014';
	end if;

	-- Determine the venue's currency, creating one if the proposal didn't name
	-- an existing currency to share.
	_currency := _proposal.currency;
	if _currency is null then
		if _proposal.payment_free then
			-- A payment-free venue still needs a (hidden) currency, but no minters
			-- were proposed, so the approving steward holds it.
			_minter_ids := array[_caller];
		else
			-- Whoever has an account mints; if nobody does, the approving steward holds the
			-- currency until the venue names someone. currencies_minters_check requires at
			-- least one, and a community adopting the platform often has not found an
			-- independent minter yet — refusing the venue until it has is the barrier this
			-- replaces. The steward may also be one of the editors above, and so an admin of
			-- this venue: that overlap is permitted, for as long as the venue needs it. The
			-- venue page discloses it to everyone who is neither an admin nor a minter,
			-- which is the safeguard that replaced forbidding it.
			select array_agg(id) into _minter_ids from public.scholars where email = any(_proposal.minters);
			if _minter_ids is null then
				_minter_ids := array[_caller];
			end if;
		end if;
		insert into public.currencies (name, minters)
		values (_proposal.title || ' currency', _minter_ids)
		returning id into _currency;
	end if;

	-- Create the venue with the editors as admins. Paying venues start with a
	-- welcome amount of 10; payment-free venues grant nothing.
	insert into public.venues (title, url, admins, welcome_amount, currency, payment_free)
	values (
		_proposal.title, _proposal.url, _editor_ids,
		case when _proposal.payment_free then 0 else 10 end,
		_currency, _proposal.payment_free
	) returning id into _venue;

	-- Link the proposal to the venue it produced.
	update public.proposals set venue = _venue where id = _proposal_id;

	-- Create the default Editor role for the venue.
	insert into public.roles (venueid, invited, name, description)
	values (
		_venue, true, 'Editor',
		'Triages submissions, assigns meta-reviewers, and makes final decisions on submissions.'
	) returning id into _role;

	-- Enroll every editor as an accepted volunteer in that role.
	foreach _editor in array _editor_ids loop
		insert into public.volunteers (scholarid, roleid, active, accepted, expertise, papers)
		values (_editor, _role, true, 'accepted', '', null);
	end loop;

	-- Create the default submission type (zero cost for payment-free venues).
	insert into public.submission_types (venue, name, description, revision_of, submission_cost)
	values (
		_venue, 'Research Article', 'The default submission type for this venue.', null,
		case when _proposal.payment_free then 0 else 10 end
	) returning id into _submission_type;

	-- Paying venues compensate the Editor role for the default submission type.
	if not _proposal.payment_free then
		insert into public.compensation (submission_type, role, amount, rationale)
		values (
			_submission_type, _role, 1,
			'It takes some time to triage a new submission and make a decision.'
		);
	end if;

	-- Gather the proposal's supporters so the application layer can email them
	-- (alongside the editors) that the venue was approved.
	select array_agg(scholarid) into _supporter_ids from public.supporters where proposalid = _proposal_id;

	-- Return the new venue plus the ids the caller needs for notifications.
	return jsonb_build_object(
		'venue_id', _venue,
		'editor_ids', to_jsonb(_editor_ids),
		'supporter_ids', to_jsonb(coalesce(_supporter_ids, array[]::uuid[])),
		'title', _proposal.title
	);
end;
$function$;
