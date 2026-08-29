-- Token scaling, phase 2: load.
--
-- Phase 1 made the counts correct. This one stops the platform doing work
-- proportional to the amount of value moved on paths where nothing needs it.

--------------------------------------
-- 1. Take `tokens` out of the realtime publication.
--
-- token_events.sql has always carried the reason for staying out of it:
--
--   "Deliberately NOT added to supabase_realtime. A 500-token mint would fan 500
--    rows out to every connected client, each firing invalidateAll()."
--
-- That was equally true of `tokens`, which was in the publication -- and it is
-- one row per token, so moving N tokens emitted N postgres_changes messages to
-- every client watching that venue or that scholar, each one re-running every
-- load function on their page. A welcome grant fired fifty; minting a
-- community's supply would fire a quarter of a million.
--
-- Nothing is lost. `transactions` is published and is ONE row per movement
-- whatever the amount, so the venue layout and the header balance subscribe to
-- that instead and wake on exactly the same events.
alter publication supabase_realtime
drop table tokens;

--------------------------------------
-- 2. Index token_events by the scholar it concerns.
--
-- export_scholar_data reads this log as `where scholar = $1 or prev_scholar = $1`
-- and neither column was indexed, so every data-rights export scanned the entire
-- log -- a table that grows by one row per token per movement and is never
-- pruned. Two indexes because an OR cannot use a composite; partial because a
-- venue-held token has null in both.
create index if not exists token_events_scholar_seq_index on public.token_events using btree (scholar, seq)
where
	scholar is not null;

create index if not exists token_events_prev_scholar_seq_index on public.token_events using btree (prev_scholar, seq)
where
	prev_scholar is not null;

--------------------------------------
-- 3. transactions.amount, so the lists can stop selecting `tokens`.
--
-- `tokens` is one UUID per token moved. The three paginated transaction lists
-- selected `*`, so every page detoasted and shipped those arrays to render a
-- column that only ever displayed their length.
--
-- Generated rather than a plain column that the RPCs maintain: it cannot drift
-- from the array it summarizes, needs no backfill, and survives the rewrite from
-- placeholder UUIDs to real ids on approval untouched, because that changes the
-- array's contents and never its length.
--
-- NOTE for anyone tempted to go further and drop `tokens` from the audit_log
-- payload, which stores the whole array twice per UPDATE: don't. replay_audit_log
-- rebuilds rows with jsonb_populate_record over exactly that payload
-- (RECOVERY.md), so a stripped column would come back null -- and `tokens` is
-- `not null`. The array's size is bounded by capping mint size, not by making
-- the audit log lie.
alter table public.transactions
add column if not exists amount integer generated always as (cardinality(tokens)) stored;

-- `tokens` is NOT NULL and cardinality() of a non-null array never is, so the
-- column cannot be null -- but Postgres does not infer that, and without this
-- every consumer of the generated TypeScript would have to handle a null that
-- cannot occur.
alter table public.transactions
alter column amount
set not null;
