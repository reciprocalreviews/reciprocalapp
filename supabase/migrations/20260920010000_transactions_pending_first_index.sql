-- Re-point the currency transaction index at the order the list actually asks for.
--
-- getCurrencyTransactions now sorts `status asc, created_at desc, seq desc`:
-- proposed transactions come first whatever their date, so that an approver's
-- outstanding work cannot sink behind pages of settled history. (Ascending is
-- proposed → approved → declined because an enum orders by declared position;
-- supabase/tests/invariants/transaction_status_order.sql is what holds that.)
--
-- transactions_currency_created_index led with `currency, created_at desc` and
-- so no longer matches that ORDER BY. A leading column the sort does not name
-- second cannot be patched around: the planner would take the index for the
-- equality on currency and then re-sort every matching row. Putting status in
-- the second position restores the ordered Index Scan — the filter and the whole
-- sort come out of one traversal, which is what makes LIMIT/OFFSET paging read
-- only the page it is asked for.
--
-- Dropped rather than kept alongside: getCurrencyTransactions was its only
-- consumer, and the new index serves the currency equality just as well for
-- anything that only filters. Two indexes on the same leading column would tax
-- every insert to serve no query.
--
-- The scholar and venue lists get nothing new. They filter `from_x = $1 OR
-- to_x = $1`, which the planner satisfies as a BitmapOr over the partial from/to
-- indexes and then sorts — a bitmap scan destroys index order, so those queries
-- were already paying for a Sort node and adding status to the ORDER BY does not
-- change their plan shape. A composite that could serve them would have to
-- duplicate itself across all four from/to columns.
drop index if exists public.transactions_currency_created_index;

create index transactions_currency_status_created_index on public.transactions using btree (currency, status, created_at desc, seq desc);
