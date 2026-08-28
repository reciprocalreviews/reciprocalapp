-- approve_venue_proposal: approving before the community has a minter.
--
-- The rule these cover: approval takes whoever has an account and never blocks on minters,
-- and the admin/minter separation is enforced at launch instead of at every write. The cases
-- that matter are the ones that used to raise — an unknown minter, and a steward approving a
-- venue they will themselves administer.
begin;

\ir ../_helpers/helpers.sql.inc
select plan(13);

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------
create temporary table ids (name text primary key, id uuid);

insert into ids (name, id)
values
	('steward', tests.create_scholar('stewie@uni.edu', true)),
	('editor', tests.create_scholar('ed@uni.edu')),
	('minter', tests.create_scholar('mint@uni.edu'));

create or replace function pg_temp.id (p_name text) returns uuid language sql as $$
	select id from ids where name = p_name;
$$;

-- Each case gets its own title so nothing has to be cleaned up between them: a venue is
-- referenced by its proposal, its roles, its volunteers and its submission types, so deleting
-- one is a foreign-key argument nobody needs to have inside a test.
create or replace function pg_temp.propose (
	p_title text,
	p_editors text[],
	p_minters text[],
	p_payment_free boolean default false
) returns uuid language plpgsql as $$
declare
	_id uuid;
begin
	insert into public.proposals (title, url, editors, minters, census, payment_free)
	values (p_title, 'https://example.com', p_editors, p_minters, 10, p_payment_free)
	returning id into _id;
	return _id;
end;
$$;

--------------------------------------------------------------------------------
-- An unknown minter no longer blocks approval; the steward holds the currency.
--------------------------------------------------------------------------------
select tests.authenticate_as(pg_temp.id('steward'));

select lives_ok(
	format('select public.approve_venue_proposal(%L)', pg_temp.propose('Unknown Minter', array['ed@uni.edu'], array['nobody@uni.edu'])),
	'approval succeeds when a proposed minter has no account'
);

select tests.clear_authentication();

select is(
	(select minters from public.currencies where id = (select currency from public.venues where title = 'Unknown Minter')),
	array[pg_temp.id('steward')],
	'the approving steward holds the currency when no proposed minter has an account'
);

select isnt(
	(select inactive from public.venues where title = 'Unknown Minter'),
	null,
	'the approved venue is created inactive, not live'
);

select is(
	(select admins from public.venues where title = 'Unknown Minter'),
	array[pg_temp.id('editor')],
	'the editors who do have accounts become the admins'
);

--------------------------------------------------------------------------------
-- A minter who does have an account is used in preference to the steward.
--------------------------------------------------------------------------------
select tests.authenticate_as(pg_temp.id('steward'));
select lives_ok(
	format('select public.approve_venue_proposal(%L)', pg_temp.propose('Partial Minters', array['ed@uni.edu'], array['mint@uni.edu', 'nobody@uni.edu'])),
	'approval succeeds when only some proposed minters have accounts'
);
select tests.clear_authentication();

select is(
	(select minters from public.currencies where id = (select currency from public.venues where title = 'Partial Minters')),
	array[pg_temp.id('minter')],
	'the minters who do have accounts hold the currency, and the steward stays out'
);

--------------------------------------------------------------------------------
-- No editor with an account is still fatal: a venue must have an admin.
--------------------------------------------------------------------------------
select tests.authenticate_as(pg_temp.id('steward'));
select throws_ok(
	format('select public.approve_venue_proposal(%L)', pg_temp.propose('No Editors', array['nobody@uni.edu'], array['mint@uni.edu'])),
	'RR014',
	null,
	'approval still refuses when no proposed editor has an account'
);
select tests.clear_authentication();

--------------------------------------------------------------------------------
-- The steward approving a venue they will administer: allowed, and it cannot go live.
--------------------------------------------------------------------------------
select tests.authenticate_as(pg_temp.id('steward'));
select lives_ok(
	format('select public.approve_venue_proposal(%L)', pg_temp.propose('Self Approved', array['stewie@uni.edu'], array['nobody@uni.edu'])),
	'a steward may approve a venue they are an editor of, holding its currency in the interim'
);
select tests.clear_authentication();

select throws_ok(
	format('update public.venues set inactive = null where id = %L', (select id from public.venues where title = 'Self Approved')),
	'RR015',
	null,
	'that venue cannot be switched live while its admin still mints its currency'
);

-- Handing the currency over is what unblocks it.
update public.currencies
set minters = array[pg_temp.id('minter')]
where id = (select currency from public.venues where title = 'Self Approved');

select lives_ok(
	format('update public.venues set inactive = null where id = %L', (select id from public.venues where title = 'Self Approved')),
	'once an independent minter holds the currency, the venue goes live'
);

select throws_ok(
	format('update public.currencies set minters = %L where id = %L',
		array[pg_temp.id('steward')],
		(select currency from public.venues where title = 'Self Approved')),
	'RR015',
	null,
	'and an active venue cannot take back a minter who administers it'
);

--------------------------------------------------------------------------------
-- A steward who is NOT an admin may mint for a venue permanently.
--------------------------------------------------------------------------------
select tests.authenticate_as(pg_temp.id('steward'));
select lives_ok(
	format('select public.approve_venue_proposal(%L)', pg_temp.propose('Steward Minter', array['ed@uni.edu'], array['nobody@uni.edu'])),
	'a venue whose only minter is a non-admin steward approves'
);
select tests.clear_authentication();

select lives_ok(
	format('update public.venues set inactive = null where id = %L', (select id from public.venues where title = 'Steward Minter')),
	'and goes live: holding a platform role is not itself a conflict'
);

select * from finish();
rollback;
