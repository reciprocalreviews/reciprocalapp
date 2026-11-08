-- The measurements that justify the phase-1 changes. Run against the database
-- built by scripts/scale-fixture.sql.
\set ON_ERROR_STOP on
\timing on

select v.id as venue, v.currency, v.title from public.venues v limit 1 \gset venue_

\echo '=============================================================='
\echo 'Row counts'
\echo '=============================================================='
select
	(select count(*) from public.tokens) as tokens,
	(select count(*) from public.scholars) as scholars,
	(select count(*) from public.token_events) as token_events;

\echo ''
\echo '=============================================================='
\echo 'What the app used to fetch to count a venue reserve.'
\echo 'PostgREST caps this at max_rows = 1000 and does not error, so'
\echo 'the browser counted 1000 no matter how large the reserve was.'
\echo '=============================================================='
select count(*) as rows_the_client_would_have_received
from (select * from public.tokens where venue = :'venue_venue' limit 1000) capped;

select count(*) as the_real_reserve
from public.tokens where venue = :'venue_venue' and currency = :'venue_currency';

\echo ''
\echo '=============================================================='
\echo 'Balance check: count(*) on a holder + currency.'
\echo 'Expect an Index Only Scan on tokens_venue_currency_id_index.'
\echo '=============================================================='
explain (analyze, buffers, costs off)
select count(*) from public.tokens
where venue = :'venue_venue' and currency = :'venue_currency';

\echo ''
\echo '=============================================================='
\echo 'Selection: N tokens of a holder + currency, locked. This is'
\echo 'what every transfer runs, and the ORDER BY it used to carry is'
\echo 'shown beside it -- fungible tokens, so the ordering pinned'
\echo 'nothing, but it sent the planner down tokens_pkey past every'
\echo 'token already spent.'
\echo '=============================================================='
\echo '-- as _move_tokens runs it now:'
explain (analyze, buffers, costs off)
select id from public.tokens
where venue = :'venue_venue' and currency = :'venue_currency'
limit 10 for update skip locked;

\echo '-- as it used to run, for comparison:'
explain (analyze, buffers, costs off)
select id from public.tokens
where venue = :'venue_venue' and currency = :'venue_currency'
order by id limit 10 for update skip locked;

\echo ''
\echo '=============================================================='
\echo 'A scholar balance, the shape getScholarTokenCount runs on'
\echo 'every navigation.'
\echo '=============================================================='
explain (analyze, buffers, costs off)
select count(*) from public.tokens
where scholar = (select s.id from public.scholars s join auth.users u on u.id = s.id
	where u.email like 'scale-%@test.local' limit 1);

\echo ''
\echo '=============================================================='
\echo 'currency_holder_counts: the three numbers the currency page'
\echo 'used to compute by downloading every token row in the currency.'
\echo '=============================================================='
select public.currency_holder_counts(:'venue_currency');

\echo ''
\echo '=============================================================='
\echo 'scholar_balances over a whole 5,000-scholar roster. As a'
\echo 'PostgREST .in() this was a ~185KB URL and an HTTP 414.'
\echo '=============================================================='
explain (analyze, buffers, costs off)
select * from public.scholar_balances(
	:'venue_currency',
	(select array_agg(s.id) from public.scholars s join auth.users u on u.id = s.id
		where u.email like 'scale-%@test.local')
);
