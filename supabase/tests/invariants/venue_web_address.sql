-- Behavioural tests for a venue's web address.
--
-- The address is what URLs, emails, and copy-paste snippets are built from, so three
-- properties have to hold in the database and not merely in the interface that writes it:
--
--   1. The format rule is enforced, including the exclusion of anything UUID-shaped —
--      the venue resolver picks a column by looking at the segment, so an address that
--      could pass for an id would make that a guess.
--   2. Addresses are globally unique, and "no address" is not an address, so every venue
--      that has not chosen one coexists with every other.
--   3. A venue cannot be activated without one — but only the TRANSITION is guarded, so
--      every venue that was already live before addresses existed stays editable.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

select tests.clear_authentication();
select tests.create_scholar('vwa_admin@test.local') as admin \gset
select tests.create_scholar('vwa_minter@test.local') as minter \gset
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as other \gset

-- ---- 1. Format ----------------------------------------------------------------
select lives_ok(
	$$ update public.venues set slug = 'acm-chi' where id = $$ || quote_literal(:'ven'),
	'a well-formed address is accepted'
);

select lives_ok(
	$$ update public.venues set slug = 'sigcse2027' where id = $$ || quote_literal(:'ven'),
	'digits after the first letter are accepted'
);

-- Three letters is the contested case, so four is the floor.
select throws_ok(
	$$ update public.venues set slug = 'chi' where id = $$ || quote_literal(:'ven'),
	'23514',
	null,
	'an address shorter than four characters is refused'
);

select throws_ok(
	$$ update public.venues set slug = 'ACM-CHI' where id = $$ || quote_literal(:'ven'),
	'23514',
	null,
	'an uppercase address is refused'
);

select throws_ok(
	$$ update public.venues set slug = '-acm-chi' where id = $$ || quote_literal(:'ven'),
	'23514',
	null,
	'a leading hyphen is refused'
);

select throws_ok(
	$$ update public.venues set slug = 'acm-chi-' where id = $$ || quote_literal(:'ven'),
	'23514',
	null,
	'a trailing hyphen is refused'
);

select throws_ok(
	$$ update public.venues set slug = 'acm--chi' where id = $$ || quote_literal(:'ven'),
	'23514',
	null,
	'a doubled hyphen is refused'
);

select throws_ok(
	$$ update public.venues set slug = '2027chi' where id = $$ || quote_literal(:'ven'),
	'23514',
	null,
	'an address starting with a digit is refused'
);

-- The one that a charset rule alone would let through: every character is legal, no
-- hyphen is doubled, it starts with a letter, and it is 36 characters long.
select throws_ok(
	$$ update public.venues set slug = 'abcdef12-3456-7890-abcd-ef1234567890' where id = $$
		|| quote_literal(:'ven'),
	'23514',
	null,
	'an address shaped like a UUID is refused'
);

-- ---- 2. Uniqueness ------------------------------------------------------------
update public.venues set slug = 'acm-chi' where id = :'ven';

select throws_ok(
	$$ update public.venues set slug = 'acm-chi' where id = $$ || quote_literal(:'other'),
	'23505',
	null,
	'two venues cannot hold the same address'
);

-- Null is not a value: the unique index treats nulls as distinct, which is what lets every
-- venue created before addresses existed keep having none.
update public.venues set slug = null where id = :'ven';
select lives_ok(
	$$ update public.venues set slug = null where id = $$ || quote_literal(:'other'),
	'two venues may both have no address'
);

-- ---- 3. An address is required to go live -------------------------------------
update public.venues set inactive = 'configuring' where id = :'ven';

select throws_ok(
	$$ update public.venues set inactive = null where id = $$ || quote_literal(:'ven'),
	'RR016',
	'A venue needs a web address before it can be activated',
	'an address-less venue cannot be activated'
);

update public.venues set slug = 'acm-chi' where id = :'ven';
select lives_ok(
	$$ update public.venues set inactive = null where id = $$ || quote_literal(:'ven'),
	'a venue with an address can be activated'
);

-- The guard is on the transition, not the state. A venue that was already live before
-- addresses existed has none, and freezing every later edit to it — title, compensation,
-- roles — until somebody named it would have been a far worse rule than the one it enforces.
update public.venues set slug = null where id = :'ven';
select lives_ok(
	$$ update public.venues set title = 'Renamed While Live' where id = $$ || quote_literal(:'ven'),
	'an already-active venue with no address is still editable'
);

select is(
	(select inactive from public.venues where id = :'ven'),
	null,
	'and it is still active'
);

select * from finish();
rollback;
