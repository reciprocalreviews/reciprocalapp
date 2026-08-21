-- Make a decided transaction actually immutable, and make its amount unforgeable.
--
-- The column grants already lock the identity columns: `creator`, `created_at`,
-- `from_*`, `to_*`, `currency`, `purpose`, `seq` and `id` cannot be written by a
-- client at all. What they cannot express is a rule that depends on the row's
-- CURRENT state, and two such rules matter here.
--
-- 1. TERMINALITY. `status`, `tokens`, `decliner` and `decline_reason` are
--    writable because a proposed transaction has to become approved or declined.
--    Nothing stopped that happening twice. An approved transfer — tokens already
--    moved, recorded in token_events — could be flipped to `declined` afterwards,
--    leaving the ledger saying value moved and the transaction saying it was
--    refused. It also made approve-vs-decline a race with two winners: the app's
--    decline path reads the row, then updates on `id` alone, so an approval
--    landing in between is simply overwritten.
--
-- 2. AMOUNT PRESERVATION. `transactions` has no amount column; the amount IS
--    cardinality(tokens). Since `tokens` is writable, the amount was writable —
--    a proposed row carrying N placeholder UUIDs could be approved with a
--    different number of real ones, and the transaction would then describe a
--    transfer that never happened at that size. Every legitimate path already
--    preserves cardinality: approve_transaction sizes its work from
--    cardinality(_txn.tokens), and create_submission and transfer_tokens fill
--    exactly as many ids as they reserved. This makes that a rule rather than a
--    habit.
--
-- A trigger rather than a policy or a grant, because both of those decide by WHO
-- is asking; this decides by what the row already is, and must apply equally to
-- the SECURITY DEFINER RPCs and to anyone at a psql prompt.
--
-- A restore is unaffected: data loads with session_replication_role = replica,
-- which suppresses user triggers, so historical rows arrive without being judged
-- against rules they predate. That is the same mechanism the append-only logs
-- rely on (see RECOVERY.md § Restoring, step 5).
create or replace function public.transactions_immutable () returns trigger language plpgsql
set
	search_path='' as $$
begin
	-- Once decided, a transaction is a record of something that happened.
	if old.status <> 'proposed' then
		if (new.status, new.tokens, new.decliner, new.decline_reason)
			is distinct from
			(old.status, old.tokens, old.decliner, old.decline_reason) then
			raise exception 'This transaction was already % and cannot be changed', old.status
				using errcode = 'RR005';
		end if;
	end if;

	-- The token count is the amount. It may be filled in, never resized.
	if cardinality(new.tokens) is distinct from cardinality(old.tokens) then
		raise exception 'A transaction cannot change how many tokens it moves (% to %)',
			cardinality(old.tokens), cardinality(new.tokens)
			using errcode = 'RR005';
	end if;

	return new;
end;
$$;

alter function public.transactions_immutable () OWNER to "postgres";

create or replace trigger transactions_immutable_check before
update on public.transactions for each row
execute function public.transactions_immutable ();
