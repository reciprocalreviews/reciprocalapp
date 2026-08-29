-- A community-sized token fixture, for measuring the things that only go wrong
-- at scale.
--
-- WHY THIS EXISTS
--
-- `public.tokens` holds one row per token and every balance is count(*) over it,
-- so the cost of every read and every transfer scales with the amount of value
-- in the system rather than with how often it moves. None of that is visible
-- against supabase/seed.sql, which mints a few hundred tokens: the queries are
-- fast, the counts are right, and the truncation that made several of those
-- counts WRONG only begins above a thousand rows.
--
-- One research community of 5,000 scholars holding 50 tokens each is 250,000
-- rows in a single currency -- and all of them sit in the venue reserve before
-- they are distributed. That is the shape this builds.
--
-- USAGE
--
--   npm run reset                                   # start from the seed
--   npm run scale:fixture                           # ~250k tokens, 5k scholars
--   npm run scale:check                             # the numbers, and their plans
--
-- Destructive and local-only: it writes directly to public.tokens, bypassing the
-- RPCs, so it leaves the token_events log full of unattributed movements and
-- reconcile_ledger will (correctly) report them. Run `npm run reset` afterwards.
-- Never point this at staging or production.
\set ON_ERROR_STOP on

\set scholars 5000
\set per_scholar 50

begin;

-- The venue and currency the seed already created.
create temporary table target as
select v.id as venue, v.currency as currency from public.venues v limit 1;

-- 5,000 scholars. Inserted in bulk rather than through tests.create_scholar,
-- which is one plpgsql call per row and takes minutes at this count.
insert into auth.users (
	instance_id, id, aud, role, email,
	encrypted_password, email_confirmed_at,
	raw_app_meta_data, raw_user_meta_data,
	created_at, updated_at,
	confirmation_token, recovery_token, email_change_token_new, email_change
)
select
	'00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
	'scale-' || n || '@test.local',
	'', now(),
	'{"provider":"email","providers":["email"]}', '{}',
	now(), now(), '', '', '', ''
from generate_series(1, :scholars) n;

-- public.scholars is written by the on_auth_user_created trigger, so the rows
-- above have already produced matching scholars. Identified by joining through
-- auth.users rather than by public.scholars.email: handle_new_scholar copies
-- only id, orcid and name, so a scholar created the ordinary way has a null
-- email and the obvious `where email like ...` matches nothing.
create temporary table scale_scholars as
select s.id
from public.scholars s
join auth.users u on u.id = s.id
where u.email like 'scale-%@test.local';

-- Twice the supply, minted into the reserve. Half is distributed below; the
-- other half stays put, so the fixture holds BOTH shapes that matter at once --
-- a reserve the size of a community's undistributed supply, and 5,000 scholars
-- holding individual balances. Measuring only the distributed state would leave
-- the reserve queries (which is to say, every payout) looking free.
insert into public.tokens (currency, venue, scholar)
select t.currency, t.venue, null
from target t, generate_series(1, :scholars * :per_scholar * 2);

commit;

-- Distribute 50 to each scholar, in one statement per scholar-batch rather than
-- 5,000 RPC calls: the point of the fixture is the resulting SHAPE, not to
-- exercise the grant path (move_tokens_rpc.sql covers that).
begin;

with numbered as (
	select id, ((row_number() over (order by id)) - 1) / :per_scholar as bucket
	from public.tokens
	where venue = (select venue from target) and currency = (select currency from target)
	order by id
	limit :scholars * :per_scholar
),
recipients as (
	select id as scholar, (row_number() over (order by id)) - 1 as bucket
	from scale_scholars
)
update public.tokens tk
set venue = null, scholar = r.scholar
from numbered n
join recipients r on r.bucket = n.bucket
where tk.id = n.id;

commit;

-- Transactions, so the RLS policy on them can be measured too. One approved
-- venue->scholar payment per scholar, plus a proposed one, which is roughly the
-- ratio a venue accumulates. The token arrays are deliberately small: it is the
-- POLICY that is being measured here, not the arrays.
begin;

insert into public.transactions (
	creator, from_scholar, from_venue, to_scholar, to_venue,
	tokens, currency, purpose, status
)
select
	s.id, null, t.venue, s.id, null,
	array[gen_random_uuid()], t.currency, 'scale fixture payment', 'approved'
from scale_scholars s, target t;

insert into public.transactions (
	creator, from_scholar, from_venue, to_scholar, to_venue,
	tokens, currency, purpose, status
)
select
	s.id, s.id, null, null, t.venue,
	array[gen_random_uuid()], t.currency, 'scale fixture charge', 'proposed'
from scale_scholars s, target t;

commit;

analyze public.tokens;

analyze public.transactions;
