-- Close three write holes that let a signed-in scholar move value without a
-- record, and let a minter erase the record.
--
-- 1. public.tokens was writable directly from the browser. `grant all on
--    public.tokens to authenticated` plus an UPDATE policy whose WITH CHECK was
--    `true` meant the owning scholar could PATCH /rest/v1/tokens and reassign a
--    token to anyone with NO transactions row written at all. Because WITH CHECK
--    did not pin `currency` either, and balances are computed as count(*) of
--    token rows, a scholar could also rewrite a token's currency and counterfeit
--    value in a currency they were never granted.
--
--    All legitimate token movement already goes through the SECURITY DEFINER
--    RPCs (mint_tokens, transfer_tokens, approve_transaction, complete_assignment,
--    mark_submission_done, create_submission, bulk_import_submissions), which are
--    unaffected by grants and policies and already re-implement these checks in
--    their own bodies. Every `from('tokens')` call site in src/ is a select, so
--    nothing in the application uses the direct write path.
--
-- 2. The policy named "transactions cannot be deleted" did the opposite of its
--    name: its USING clause GRANTED delete to any minter of the currency. A
--    currency minter could permanently erase approved transfer history while the
--    tokens those rows described stayed put, silently orphaning the audit trail.
--
-- 3. `grant all` confers INSERT on EVERY column of public.transactions, so a
--    client could supply its own `id` or backdate `created_at`. The UPDATE grant
--    was already narrowed to the mutable columns for exactly this reason; INSERT
--    needs the same treatment. (A column-level REVOKE is a no-op while a
--    table-wide GRANT ALL confers the privilege, so the grant must be removed and
--    re-granted, not merely revoked.)

--------------------------------------
-- 1. tokens: writable only by the SECURITY DEFINER RPCs.
revoke insert,
update,
delete on public.tokens
from
	authenticated,
	anon;

drop policy if exists "only minters can create tokens" on public.tokens;

drop policy if exists "owners, admins, and priority-0 roles can update tokens" on public.tokens;

-- Kept as explicit deny policies rather than no policy at all: a table with RLS
-- enabled and no policy for a command already denies it, but naming the denial
-- documents the intent and lets policies_are() assert it in the pgTAP suite.
create policy "tokens are only created by definer rpcs" on public.tokens for INSERT to authenticated
with
	check (false);

create policy "tokens are only updated by definer rpcs" on public.tokens
for update
	to authenticated using (false);

--------------------------------------
-- 2. transactions: nobody deletes history.
drop policy if exists "transactions cannot be deleted" on public.transactions;

create policy "transactions cannot be deleted" on public.transactions for DELETE to authenticated using (false);

revoke delete on public.transactions
from
	authenticated,
	anon;

--------------------------------------
-- 3. transactions: a client may propose a transaction, but may not choose its
-- identity or its timestamp. Mirrors the UPDATE allowlist above it.
revoke insert on public.transactions
from
	authenticated;

-- anon retained table-level INSERT and UPDATE from the original `grant all`: the
-- earlier revoke named only `authenticated`. No policy admits anon to either
-- command, so RLS denies them today, but leaving the privilege in place means any
-- future policy written `to public` would silently open a write path for
-- unauthenticated callers. Take the privilege away too.
revoke insert,
update on public.transactions
from
	anon;

grant insert (
	creator,
	from_scholar,
	from_venue,
	to_scholar,
	to_venue,
	tokens,
	currency,
	purpose,
	status
) on public.transactions to authenticated;
