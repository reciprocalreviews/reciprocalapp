-- Atomic CRUD (#136)
--
-- Several SupabaseCRUD operations were implemented as a sequence of separate
-- client-side Supabase calls. A connectivity loss between two of those calls
-- could leave the database in a partially-written, inconsistent state: tokens
-- moved with no transaction recorded, a submission inserted with orphaned
-- proposed payments, a volunteer created with no welcome grant, or a venue
-- half-provisioned. This migration moves the money- and setup-critical
-- multi-write operations into SECURITY DEFINER Postgres functions so each runs
-- inside a single database transaction — all-or-nothing.
--
-- Because SECURITY DEFINER bypasses RLS, each function re-implements, in its
-- own body, the authorization and anti-self-dealing rules that the RLS
-- policies (see tokens.sql, transactions.sql, volunteers.sql, venues.sql,
-- currencies.sql) and the no_minter_admins / no_admin_minters triggers
-- enforce on direct writes. Mirrors the established pattern of
-- complete_assignment / mark_submission_done / bulk_import_submissions.
--
-- These definitions are duplicated into the declarative schema files under
-- supabase/schemas/ (each function lives in the schema file of its primary
-- table) so contributors can find them next to the tables they operate on.

--------------------------------------------------------------------------------
-- Internal helper: record the proposed welcome grant for a volunteer.
-- Not granted to any role — only reachable from the SECURITY DEFINER functions
-- below, which run as the owner. Creates a proposed venue->scholar transaction
-- sized to the venue's welcome_amount; a minter approves it later to actually
-- mint and transfer the tokens. No-op for payment-free venues (no tokens).
--------------------------------------------------------------------------------
create or replace function public._welcome_volunteer (
	_welcomer uuid,
	_scholar uuid,
	_roleid uuid,
	_reason text
) returns void language plpgsql security definer
set
	search_path = public, pg_temp as $function$
declare
	_venue public.venues;
begin
	-- Find the venue that owns the role being volunteered for.
	select v.* into _venue
	from public.venues v
	join public.roles r on r.id = _roleid
	where v.id = r.venueid;
	-- Role or venue gone? Nothing to grant.
	if not found then
		return;
	end if;

	-- Payment-free venues have no tokens, and a zero welcome amount means there
	-- is nothing to grant — either way, do nothing.
	if _venue.payment_free or _venue.welcome_amount <= 0 then
		return;
	end if;

	-- Record the grant as a *proposed* venue->scholar transaction. The tokens
	-- are placeholders (null UUIDs) until a minter approves it via
	-- approve_transaction, which mints and transfers the real tokens.
	insert into public.transactions (
		creator, from_scholar, from_venue, to_scholar, to_venue,
		tokens, currency, purpose, status
	) values (
		_welcomer, null, _venue.id, _scholar, null,
		array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[_venue.welcome_amount]),
		_venue.currency, _reason, 'proposed'
	);
end;
$function$;

revoke execute on function public._welcome_volunteer (uuid, uuid, uuid, text) from public;

--------------------------------------------------------------------------------
-- mint_tokens: mint _amount tokens of _currency into a venue reserve and
-- record the approved mint transaction, atomically. Replaces the two-write
-- SupabaseCRUD.mintTokens (token insert + transaction insert).
-- Authorization mirrors the tokens INSERT policy (caller must be a minter) and
-- the transactions approved policy (a minter must not mint into a venue they
-- administer — self-enrichment).
--------------------------------------------------------------------------------
create or replace function public.mint_tokens (
	_currency uuid,
	_amount integer,
	_to_venue uuid,
	_purpose text
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
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
	-- Refuse self-enrichment: a minter must not mint into a venue they
	-- administer. The no_admin_minters trigger normally makes this impossible,
	-- but SECURITY DEFINER skips RLS, so we check explicitly.
	if public.isAdmin(_to_venue) then
		raise exception 'A minter cannot mint into a venue they administer';
	end if;

	-- Create the tokens, owned by the destination venue, and capture their ids.
	with inserted as (
		insert into public.tokens (currency, venue, scholar)
		select _currency, _to_venue, null from generate_series(1, _amount)
		returning id
	)
	select array_agg(id) into _token_ids from inserted;

	-- Record the matching approved mint transaction (no source, to the venue).
	insert into public.transactions (
		creator, from_scholar, from_venue, to_scholar, to_venue,
		tokens, currency, purpose, status
	) values (
		_caller, null, null, null, _to_venue,
		_token_ids, _currency, _purpose, 'approved'
	) returning id into _txn_id;

	-- Hand the new token ids and transaction id back to the caller.
	return jsonb_build_object('token_ids', to_jsonb(_token_ids), 'transaction_id', _txn_id);
end;
$function$;

revoke execute on function public.mint_tokens (uuid, integer, uuid, text) from public;
grant execute on function public.mint_tokens (uuid, integer, uuid, text) to authenticated;

--------------------------------------------------------------------------------
-- transfer_tokens: move _amount tokens of _currency from one entity to another
-- in a single statement and either finalize an existing proposed transaction or
-- record a new approved one, atomically. Replaces SupabaseCRUD.transferTokens,
-- whose per-token UPDATE loop could partially transfer on a connectivity loss.
-- Entity ids are pre-resolved by the caller; kinds are 'venueid' or 'scholarid'.
-- Authorization mirrors the tokens UPDATE policy (owner scholar, or venue
-- admin / priority-0) and the transactions approved policy (no self-enrichment
-- when moving someone else's tokens).
--------------------------------------------------------------------------------
create or replace function public.transfer_tokens (
	_currency uuid,
	_from uuid,
	_from_kind text,
	_to uuid,
	_to_kind text,
	_amount integer,
	_purpose text,
	_transaction uuid
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
declare
	_caller uuid;
	_from_scholar uuid;
	_from_venue uuid;
	_to_scholar uuid;
	_to_venue uuid;
	_token_ids uuid[];
	_txn_id uuid;
begin
	-- Identify and require an authenticated caller.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	-- A transfer must move a positive number of tokens.
	if _amount is null or _amount <= 0 then
		raise exception 'Transfer amount must be positive';
	end if;

	-- Sort the pre-resolved from/to ids into the scholar vs venue slots.
	if _from_kind = 'venueid' then _from_venue := _from; else _from_scholar := _from; end if;
	if _to_kind = 'venueid' then _to_venue := _to; else _to_scholar := _to; end if;

	-- Authorize the move and forbid self-enrichment.
	if _from_scholar is not null then
		-- Spending one's own balance: only the owner may, and there is no
		-- restriction on who receives it.
		if _caller <> _from_scholar then
			raise exception 'You can only transfer your own tokens';
		end if;
	else
		-- Moving a venue's tokens: only its admins or a priority-0 role holder may.
		if not (public.isAdmin(_from_venue) or public.isPriorityZero(_from_venue)) then
			raise exception 'You are not authorized to transfer this venue''s tokens';
		end if;
		-- And the mover must not be the recipient (or an admin of a recipient
		-- venue) — that would be paying themselves from the reserve.
		if _to_scholar is not null and _to_scholar = _caller then
			raise exception 'You cannot transfer tokens to yourself';
		end if;
		if _to_venue is not null and public.isAdmin(_to_venue) then
			raise exception 'You cannot transfer tokens to a venue you administer';
		end if;
	end if;

	-- Pick exactly _amount tokens currently owned by the source in this currency.
	select array_agg(id) into _token_ids
	from (
		select id from public.tokens
		where currency = _currency
		  and (
			(_from_scholar is not null and scholar = _from_scholar)
			or (_from_venue is not null and venue = _from_venue)
		  )
		order by id
		limit _amount
	) sub;

	-- The source must actually hold that many tokens. RR003 lets the app show
	-- the specific "insufficient tokens" message (see SupabaseCRUD.rpcErrorKey).
	if _token_ids is null or cardinality(_token_ids) < _amount then
		raise exception 'Insufficient tokens to transfer' using errcode = 'RR003';
	end if;

	-- Reassign all chosen tokens to the destination in one statement.
	update public.tokens set scholar = _to_scholar, venue = _to_venue where id = any(_token_ids);

	if _transaction is not null then
		-- Finalizing a previously proposed transfer: flip it to approved and
		-- record which tokens actually moved.
		update public.transactions set status = 'approved', tokens = _token_ids where id = _transaction;
		_txn_id := _transaction;
	else
		-- A fresh transfer (e.g. a gift): record a new approved transaction.
		insert into public.transactions (
			creator, from_scholar, from_venue, to_scholar, to_venue,
			tokens, currency, purpose, status
		) values (
			_caller, _from_scholar, _from_venue, _to_scholar, _to_venue,
			_token_ids, _currency, _purpose, 'approved'
		) returning id into _txn_id;
	end if;

	-- Return the transaction id and the tokens that moved.
	return jsonb_build_object('transaction_id', _txn_id, 'token_ids', to_jsonb(_token_ids));
end;
$function$;

revoke execute on function public.transfer_tokens (uuid, uuid, text, uuid, text, integer, text, uuid) from public;
grant execute on function public.transfer_tokens (uuid, uuid, text, uuid, text, integer, text, uuid) to authenticated;

--------------------------------------------------------------------------------
-- approve_transaction: approve a proposed transaction, minting and/or moving
-- tokens and flipping its status to 'approved', atomically. Replaces
-- SupabaseCRUD.approveTransaction, whose mint + per-token transfer + status
-- update spanned several round trips. Three branches, matching the original:
--   A) pure mint (no source, all placeholder tokens, venue recipient)
--   B) transfer (scholar or venue source), minting placeholders first when a
--      venue source needs tokens that don't exist yet.
-- Authorization mirrors the transactions UPDATE policy (giver scholar, venue
-- admin, or minter), the no-self-enrichment rule, and the tokens INSERT policy
-- (minting requires a minter).
--------------------------------------------------------------------------------
create or replace function public.approve_transaction (
	_transaction_id uuid
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
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
	_spending_own := (_txn.from_scholar is not null and _txn.from_scholar = _caller);
	if not _spending_own then
		if _txn.to_scholar is not null and _txn.to_scholar = _caller then
			raise exception 'You cannot approve a transaction that pays you' using errcode = 'RR002';
		end if;
		if _txn.to_venue is not null and public.isAdmin(_txn.to_venue) then
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

	return jsonb_build_object('transaction_id', _transaction_id, 'token_ids', to_jsonb(_token_ids));
end;
$function$;

revoke execute on function public.approve_transaction (uuid) from public;
grant execute on function public.approve_transaction (uuid) to authenticated;

--------------------------------------------------------------------------------
-- create_submission: create the proposed payment transactions for each paying
-- author, immediately approve the submitter's own charge (moving their tokens
-- to the venue), and insert the submission with aligned authors/payments/
-- transactions arrays — all atomically. Replaces SupabaseCRUD.createSubmission,
-- which could leave orphaned proposed transactions or violate the submissions
-- array-cardinality CHECK constraints on a partial failure. Author resolution
-- and balance pre-checks (reads) stay in the application layer; this function
-- receives already-resolved author ids and their token charges.
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- create_volunteer: insert a volunteer record and, when this is the scholar's
-- first role and compensation is requested, record the proposed welcome grant —
-- atomically. Replaces SupabaseCRUD.createVolunteer, where the volunteer insert
-- and welcome grant were separate writes. Authorization mirrors the volunteers
-- INSERT policy (venue admin, or self for a non-invite-only role).
--------------------------------------------------------------------------------
create or replace function public.create_volunteer (
	_scholarid uuid,
	_roleid uuid,
	_accepted boolean,
	_compensate boolean,
	_papers integer
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
declare
	_caller uuid;
	_venueid uuid;
	_invited boolean;
	_existing_count integer;
	_volunteer_id uuid;
begin
	-- Identify and require an authenticated caller.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- Look up the role's venue and whether it is invite-only.
	select venueid, invited into _venueid, _invited from public.roles where id = _roleid;
	if _venueid is null then
		raise exception 'Role not found';
	end if;

	-- A venue admin may add anyone; otherwise a scholar may only add themselves,
	-- and only to a role that is not invite-only.
	if not (public.isAdmin(_venueid) or (_caller = _scholarid and not _invited)) then
		raise exception 'You are not authorized to volunteer for this role';
	end if;

	-- No duplicate volunteering for the same role. RR004 surfaces the specific
	-- "already volunteered" message.
	if exists (select 1 from public.volunteers where scholarid = _scholarid and roleid = _roleid) then
		raise exception 'Already volunteered for this role' using errcode = 'RR004';
	end if;

	-- Welcome tokens are granted only once, on the scholar's very first role, so
	-- count their existing volunteer rows before inserting the new one.
	select count(*) into _existing_count from public.volunteers where scholarid = _scholarid;

	-- Create the volunteer record.
	insert into public.volunteers (scholarid, roleid, active, accepted, expertise, papers)
	values (
		_scholarid, _roleid, _accepted,
		case when _accepted then 'accepted'::public.invited else 'invited'::public.invited end,
		'', _papers
	) returning id into _volunteer_id;

	-- First role and compensation requested? Record the welcome grant in the
	-- same transaction, so the volunteer can never exist without it.
	if _existing_count = 0 and _compensate then
		perform public._welcome_volunteer(_caller, _scholarid, _roleid, 'Welcome tokens for volunteering');
	end if;

	-- Return the new volunteer id.
	return jsonb_build_object('volunteer_id', _volunteer_id);
end;
$function$;

revoke execute on function public.create_volunteer (uuid, uuid, boolean, boolean, integer) from public;
grant execute on function public.create_volunteer (uuid, uuid, boolean, boolean, integer) to authenticated;

--------------------------------------------------------------------------------
-- accept_role_invite: respond to a role invitation and, when accepting a first
-- role, record the proposed welcome grant — atomically. Replaces
-- SupabaseCRUD.acceptRoleInvite. Authorization mirrors the volunteers UPDATE
-- policy (only the volunteering scholar).
--------------------------------------------------------------------------------
create or replace function public.accept_role_invite (
	_volunteer_id uuid,
	_response public.invited
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
declare
	_caller uuid;
	_v public.volunteers;
	_total integer;
begin
	-- Identify and require an authenticated caller.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- Load the invitation; only the invited scholar may respond to it.
	select * into _v from public.volunteers where id = _volunteer_id;
	if not found then
		raise exception 'Volunteer record not found';
	end if;
	if _caller <> _v.scholarid then
		raise exception 'You can only respond to your own invitations';
	end if;

	-- Count the scholar's volunteer rows to detect a first-role acceptance.
	select count(*) into _total from public.volunteers where scholarid = _v.scholarid;

	-- Apply the response and (re)activate the record.
	update public.volunteers set active = true, accepted = _response where id = _volunteer_id;

	-- Accepting a first invitation earns the welcome grant, recorded atomically.
	if _total = 1 and _v.accepted = 'invited' and _response = 'accepted' then
		perform public._welcome_volunteer(_v.scholarid, _v.scholarid, _v.roleid, 'Welcome tokens for accepting role invite');
	end if;

	-- Return the volunteer id that was updated.
	return jsonb_build_object('volunteer_id', _volunteer_id);
end;
$function$;

revoke execute on function public.accept_role_invite (uuid, public.invited) from public;
grant execute on function public.accept_role_invite (uuid, public.invited) to authenticated;

--------------------------------------------------------------------------------
-- approve_venue_proposal: provision a whole venue from an approved proposal —
-- currency (if none was proposed), venue, editor role, editor volunteers,
-- default submission type, and default compensation — and link the proposal to
-- the new venue, all atomically. Replaces SupabaseCRUD.approveVenueProposal,
-- whose ~8 sequential writes could orphan records on a partial failure.
-- Authorization: stewards only. Emails to editors and supporters are dispatched
-- by the application layer from the returned ids.
--------------------------------------------------------------------------------
create or replace function public.approve_venue_proposal (
	_proposal_id uuid
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
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

	-- Resolve the proposed editor emails to scholar ids; every editor must
	-- already have an account.
	select array_agg(id) into _editor_ids from public.scholars where email = any(_proposal.editors);
	if _editor_ids is null or cardinality(_editor_ids) < cardinality(_proposal.editors) then
		raise exception 'Not all proposed editors have accounts';
	end if;

	-- Determine the venue's currency, creating one if the proposal didn't name
	-- an existing currency to share.
	_currency := _proposal.currency;
	if _currency is null then
		if _proposal.payment_free then
			-- A payment-free venue still needs a (hidden) currency, but no minters
			-- were proposed. The approving steward becomes the sole minter —
			-- stewards are never venue admins, so no_admin_minters passes.
			_minter_ids := array[_caller];
		else
			-- Resolve the proposed minter emails; every minter must have an account.
			select array_agg(id) into _minter_ids from public.scholars where email = any(_proposal.minters);
			if _minter_ids is null or cardinality(_minter_ids) < cardinality(_proposal.minters) then
				raise exception 'Not all proposed minters have accounts';
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

revoke execute on function public.approve_venue_proposal (uuid) from public;
grant execute on function public.approve_venue_proposal (uuid) to authenticated;
