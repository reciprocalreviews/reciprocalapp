-- Welcome grants settle immediately instead of awaiting minter approval.
--
-- DESIGN.md's venue section says welcome tokens "should be minted and given"
-- when a scholar first volunteers. The implementation instead recorded a
-- *proposed* venue->scholar transaction that a minter had to approve — friction
-- that lands exactly where it hurts most: a new author who volunteers in order
-- to afford a submission charge is blocked on minter latency before they can
-- pay. The amount is standing venue policy (venues.welcome_amount, set by the
-- venue's admins, granted at most once per scholar on their first role), not a
-- discretionary mint, so per-grant minter approval adds no oversight the
-- welcome_amount setting doesn't already provide. Minters still approve every
-- other mint.
--
-- The settled grant mirrors approve_transaction's venue-source branch: draw
-- from the venue's reserve, minting only any shortfall into the reserve first,
-- and record one approved venue->scholar transaction. Both token writes are
-- attributed to that transaction via the app.txn GUC so the token ledger stays
-- explained (token_events.txn is never null for these movements).

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
	_txn_id uuid;
	_available integer;
	_shortfall integer;
	_token_ids uuid[];
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

	-- Attribute both token writes below (the shortfall mint and the transfer) to
	-- the transaction recorded at the end. The id is generated up front because
	-- the tokens are written before the transaction row exists, and the
	-- token_events trigger reads app.txn at the moment of the write.
	_txn_id := gen_random_uuid();
	perform set_config('app.txn', _txn_id::text, true);

	-- Draw from the venue's reserve, minting only the shortfall into it first —
	-- the same shape approve_transaction gives a venue-sourced transfer.
	select count(*) into _available
	from public.tokens
	where currency = _venue.currency and venue = _venue.id;
	_shortfall := greatest(0, _venue.welcome_amount - _available);
	if _shortfall > 0 then
		insert into public.tokens (currency, venue, scholar)
		select _venue.currency, _venue.id, null from generate_series(1, _shortfall);
	end if;

	-- Choose the granted tokens and move them to the scholar.
	select array_agg(id) into _token_ids
	from (
		select id from public.tokens
		where currency = _venue.currency and venue = _venue.id
		order by id
		limit _venue.welcome_amount
	) sub;
	update public.tokens set venue = null, scholar = _scholar where id = any(_token_ids);

	-- Record the settled grant as one approved venue->scholar transaction.
	insert into public.transactions (
		id, creator, from_scholar, from_venue, to_scholar, to_venue,
		tokens, currency, purpose, status
	) values (
		_txn_id, _welcomer, null, _venue.id, _scholar, null,
		_token_ids, _venue.currency, _reason, 'approved'
	);

	-- Clear the attribution, so a later token write in this same database
	-- transaction that is NOT part of this grant is recorded as unattributed
	-- rather than borrowing this transaction's id.
	perform set_config('app.txn', '', true);
end;
$function$;

revoke execute on function public._welcome_volunteer (uuid, uuid, uuid, text) from public;
