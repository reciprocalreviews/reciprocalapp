-- Give transactions a monotonic ordering column and the indexes it has never had.
--
-- Two problems, one fix.
--
-- 1. ORDERING. `created_at` defaults to now(), which in PostgreSQL is the
--    *transaction start* time — identical for every row a single statement or
--    function writes. create_submission inserts one charge per author in one
--    transaction, so those rows share a timestamp exactly. The table has no
--    other monotonic column (there is not a single sequence anywhere in this
--    schema), and `id` is a random uuid, so ties are unresolvable.
--
--    That is not cosmetic. Every transaction list paginates with
--    `.order('created_at', desc).range(...)`, and a LIMIT/OFFSET over a
--    non-deterministic sort order can return the same row on two pages and skip
--    another entirely. `seq` gives the sort a unique tiebreaker.
--
-- 2. INDEXES. `transactions` had none at all — not on created_at, not on any of
--    the from/to columns, not on currency. Every list was a sequential scan plus
--    a sort. The indexes below are chosen from the predicates the application
--    and the remind edge function actually issue, not speculatively.
--
-- A caveat worth recording: a sequence gives *insertion* order, not *commit*
-- order, so under concurrency a row with a lower seq can become visible after
-- one with a higher seq. At this write volume that never matters, but anything
-- that treats seq as a replication watermark should compare against
-- pg_snapshot_xmin(pg_current_snapshot()) rather than assume max(seq) is final.
--------------------------------------
-- Ordering
alter table public.transactions
add column seq bigint;

-- Backfill deterministically: existing history has no true order, so we impose
-- the best available one — creation time, with the uuid as a stable tiebreaker
-- so re-running this on a copy produces identical numbering.
with
	ordered as (
		select
			id,
			row_number() over (
				order by
					created_at,
					id
			) as n
		from
			public.transactions
	)
update public.transactions t
set
	seq=o.n
from
	ordered o
where
	o.id=t.id;

alter table public.transactions
alter column seq
set
	not null;

create sequence public.transactions_seq_seq owned by public.transactions.seq;

select
	setval(
		'public.transactions_seq_seq',
		coalesce(
			(
				select
					max(seq)
				from
					public.transactions
			),
			0
		)+1,
		false
	);

alter table public.transactions
alter column seq
set default nextval('public.transactions_seq_seq');

alter table public.transactions
add constraint transactions_seq_key unique (seq);

-- A column DEFAULT that calls nextval() requires the INSERTing role to hold
-- USAGE on the sequence; without this, every client-side transaction insert
-- fails with "permission denied for sequence". The SECURITY DEFINER RPCs are
-- unaffected either way, since they run as the owner.
--
-- anon is deliberately omitted: its INSERT on transactions was revoked in
-- 20260802010000, so it has no way to reach this default.
grant
usage on sequence public.transactions_seq_seq to authenticated,
service_role;

-- seq is not client-settable. The INSERT and UPDATE column allowlists from
-- 20260802010000 name only the columns a caller may supply, and seq is not among
-- them, so a client can neither choose its place in history nor rewrite it.
--------------------------------------
-- Indexes
--
-- getCurrencyTransactions filters on currency and sorts by created_at desc. This
-- composite covers both, so an ordered Index Scan can satisfy the ORDER BY with
-- no Sort node at all; seq is the tiebreaker that makes the pagination stable.
--
-- On a near-empty table the planner still picks a Bitmap Heap Scan plus a Sort,
-- because at that size the bitmap plan is genuinely cheaper — that is the
-- planner being right, not the index being wrong. Verify the ordered path with
-- `set enable_bitmapscan = off` rather than concluding the index is unused.
create index transactions_currency_created_index on public.transactions using btree (currency, created_at desc, seq desc);

-- getScholarTransactions and getVenueTransactions each filter with
-- `from_x = $1 OR to_x = $1`, which the planner satisfies as a BitmapOr over two
-- indexes. Partial, because these columns are mutually exclusive by CHECK
-- constraint and roughly half the table is null in each.
--
-- from_scholar additionally serves getOutgoingPendingTransactions, and from_venue
-- serves the remind edge function's pending-transaction sweep.
create index transactions_from_scholar_index on public.transactions using btree (from_scholar)
where
	from_scholar is not null;

create index transactions_to_scholar_index on public.transactions using btree (to_scholar)
where
	to_scholar is not null;

create index transactions_from_venue_index on public.transactions using btree (from_venue)
where
	from_venue is not null;

create index transactions_to_venue_index on public.transactions using btree (to_venue)
where
	to_venue is not null;

-- Not added, deliberately:
--   * a GIN index on `tokens` — nothing queries the array yet. It becomes worth
--     adding with the reconciliation checks that need "which transaction moved
--     token X".
--   * partial indexes on `status = 'proposed'` — all three pending-transaction
--     queries pair that status with currency, from_scholar, or from_venue, each
--     of which is already indexed above, and proposed rows are a small minority.
--     Revisit if those queries show up slow rather than adding them on faith.
