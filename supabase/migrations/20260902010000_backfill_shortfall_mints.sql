-- Repair the shortfall mints that no transaction credited.
--
-- Runs after 20260902000000, which is what stops new ones being created. The
-- order matters: with the fix first, no welcome grant can re-create drift behind
-- the repair.
--
-- Expected to be a no-op on every development and CI database -- seed.sql creates
-- tokens directly rather than through a shortfall path, so none has this shape.
-- On production it writes one approved mint transaction per (transfer, reserve)
-- that minted without one. See the function's own comments for why it refuses
-- rather than guesses, and why created_at is not backdated.
--------------------------------------

--------------------------------------
-- Repairing the mints that were never recorded
--
-- Before 20260902000000, the two shortfall-mint paths created tokens in a venue's
-- reserve and recorded only the transfer that carried them out, so those venues
-- hold tokens their own history does not account for. This writes the missing
-- credit, and nothing else.
--
-- The evidence is in token_events and is unambiguous: a mint event whose txn is a
-- TRANSFER rather than a mint is exactly a shortfall mint. mint_tokens and
-- approve_transaction's Branch A both point their mint events at a transaction
-- with no source at all, so there are no false positives.
--
-- A function rather than a bare `do` block in the migration, because a restore
-- from a backup predating the repair brings the drift back and will NOT re-run the
-- migration -- RECOVERY.md can then simply call this, with no second copy of the
-- SQL to drift out of step. Underscore-prefixed, so definer_grants.sql's
-- owner-only assertion already covers it.
create or replace function public._backfill_shortfall_mints () returns integer language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_bad integer;
	_n integer;
begin
	-- Refuse rather than guess. A mint that landed on a scholar, or one tied to a
	-- transfer that was never approved, is a shape this repair has no evidence for;
	-- and backfilling a token that is gone or has changed currency would trade a
	-- conservation violation for a dangling_token_refs one, which is not a repair.
	select count(*) into _bad
	from public.token_events e
	join public.transactions x on x.id = e.txn
	left join public.tokens t on t.id = e.token
	where e.op = 'mint'
		and (x.from_scholar is not null or x.from_venue is not null)
		and (
			e.venue is null
			or x.status <> 'approved'
			or t.id is null
			or t.currency <> e.currency
		);
	if _bad > 0 then
		raise exception
			'% shortfall mint(s) are not in the shape this repair understands; investigate before backfilling', _bad;
	end if;

	-- One approved mint transaction per (transfer, reserve), crediting the reserve
	-- with the tokens that were minted into it.
	--
	-- created_at is deliberately NOT backdated. These rows are being written today
	-- and transactions.seq says so regardless, so a backdated created_at would only
	-- make the two disagree -- and a definite order the platform assigns is exactly
	-- what seq is for. The original date goes in the purpose instead, where it is
	-- honest and readable. Recording a missing entry is not the same as inventing
	-- one that was there all along.
	--
	-- creator is the creator of the transfer that caused the mint: already known to
	-- satisfy the FK, and the person accountable for the act. NOT token_events.actor,
	-- which has no FK and is nulled by erasure, so it can name a row that is gone.
	with shortfall as (
		select e.txn as transfer_txn, e.venue as reserve, e.currency as cur,
			x.creator as creator, x.purpose as purpose, x.created_at as created_at,
			array_agg(e.token order by e.seq) as tokens
		from public.token_events e
		join public.transactions x on x.id = e.txn
		where e.op = 'mint'
			and (x.from_scholar is not null or x.from_venue is not null)
		group by 1, 2, 3, 4, 5, 6
	),
	written as (
		insert into public.transactions (
			id, creator, from_scholar, from_venue, to_scholar, to_venue,
			tokens, currency, purpose, status
		)
		select
			-- Deterministic, so a second run is a no-op rather than a second credit.
			md5('shortfall-mint-backfill:' || s.transfer_txn::text || ':' || s.reserve::text)::uuid,
			s.creator, null, null, null, s.reserve,
			s.tokens, s.cur,
			format('Minted %s to cover %s (recorded retroactively)',
				to_char(s.created_at at time zone 'utc', 'YYYY-MM-DD'), s.purpose),
			'approved'
		from shortfall s
		on conflict (id) do nothing
		returning 1
	)
	select count(*) into _n from written;

	raise notice 'backfilled % shortfall mint transaction(s)', _n;
	return _n;
end;
$function$;

alter function public._backfill_shortfall_mints () OWNER to "postgres";

revoke
execute on function public._backfill_shortfall_mints ()
from
	public,
	anon,
	authenticated;

select public._backfill_shortfall_mints();
