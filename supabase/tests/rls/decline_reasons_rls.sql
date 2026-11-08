-- RLS tests for public.decline_reasons (#218).
--
-- Authorization model under test:
--   SELECT  authenticated scholars only; anonymous visitors cannot read.
--   INSERT  venue admins only (isAdmin(venueid)).
--   UPDATE  venue admins only (isAdmin(venueid)).
--   DELETE  venue admins only (isAdmin(venueid)).
-- And the defaults: every new venue starts with five reasons, through a trigger that
-- no client can call.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('dr_minter@test.local') as minter \gset
select tests.create_scholar('dr_admin@test.local') as admin \gset
select tests.create_scholar('dr_outsider@test.local') as outsider \gset
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

select id as reason from public.decline_reasons where venueid = :'ven' and rank = 0 \gset
select id as reason_del from public.decline_reasons where venueid = :'ven' and rank = 4 \gset

-- ---- Defaults -----------------------------------------------------------------
select results_eq(
	$$ select text from public.decline_reasons where venueid = $$ || quote_literal(:'ven') || $$ order by rank $$,
	$$ values
		('We needed someone with different expertise.'),
		('We selected a different scholar.'),
		('We already have enough reviewers for this submission.'),
		('Other qualified scholars were in more need of tokens.'),
		('We wanted to avoid a possible conflict of interest.') $$,
	'a new venue starts with the five default decline reasons, in order'
);

select ok(
	not has_function_privilege('anon', 'public._seed_decline_reasons()', 'execute')
	and not has_function_privilege('authenticated', 'public._seed_decline_reasons()', 'execute'),
	'the seeding trigger function is not callable by clients'
);

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'decline_reasons',
	array[
		'authenticated scholars can view decline reasons',
		'only admins can create decline reasons',
		'only admins can update decline reasons',
		'only admins can delete decline reasons'
	]
);

-- ---- SELECT -------------------------------------------------------------------
select tests.authenticate_as(:'outsider');
select isnt_empty(
	$$ select 1 from public.decline_reasons where id = $$ || quote_literal(:'reason'),
	'an authenticated scholar can view a decline reason'
);

select tests.authenticate_as_anon();
select is_empty(
	$$ select 1 from public.decline_reasons where id = $$ || quote_literal(:'reason'),
	'anonymous visitors cannot view decline reasons'
);

-- ---- INSERT -------------------------------------------------------------------
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ insert into public.decline_reasons (venueid, text, rank)
	   values ( $$ || quote_literal(:'ven') || $$, 'We are not seating new reviewers this month.', 5) $$,
	'a venue admin can create a decline reason'
);

select throws_ok(
	$$ insert into public.decline_reasons (venueid, text, rank)
	   values ( $$ || quote_literal(:'ven') || $$, '   ', 6) $$,
	'23514',
	null,
	'a blank decline reason is refused'
);

select throws_ok(
	$$ insert into public.decline_reasons (venueid, text, rank)
	   values ( $$ || quote_literal(:'ven') || $$, 'We selected a different scholar.', 6) $$,
	'23505',
	null,
	'a venue cannot have the same reason twice'
);

select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ insert into public.decline_reasons (venueid, text, rank)
	   values ( $$ || quote_literal(:'ven') || $$, 'Sneaky', 7) $$,
	'42501',
	null,
	'a non-admin cannot create a decline reason'
);

-- ---- UPDATE -------------------------------------------------------------------
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ update public.decline_reasons set text = 'We needed someone with other expertise.'
	   where id = $$ || quote_literal(:'reason'),
	'a venue admin can update a decline reason'
);

-- A non-admin's UPDATE is filtered by the using clause (0 rows, no error).
select tests.authenticate_as(:'outsider');
update public.decline_reasons set text = 'Tampered' where id = :'reason';
select tests.clear_authentication();
select is(
	(select text from public.decline_reasons where id = :'reason'),
	'We needed someone with other expertise.',
	'a non-admin cannot update a decline reason (no-op)'
);

-- ---- DELETE -------------------------------------------------------------------
select tests.authenticate_as(:'outsider');
delete from public.decline_reasons where id = :'reason_del';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.decline_reasons where id = :'reason_del'),
	1,
	'a non-admin cannot delete a decline reason'
);

select tests.authenticate_as(:'admin');
select lives_ok(
	$$ delete from public.decline_reasons where id = $$ || quote_literal(:'reason_del'),
	'a venue admin can delete a decline reason'
);

select * from finish();
rollback;
