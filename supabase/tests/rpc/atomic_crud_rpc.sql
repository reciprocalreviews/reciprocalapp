-- Tests for the atomic-CRUD RPCs (#136), defined in
-- migration 20260608000000_atomic_crud.sql.
--
-- These functions are SECURITY DEFINER and therefore bypass RLS, so each one
-- re-implements the authorization and anti-self-dealing rules that the RLS
-- policies enforce on direct writes. These tests are the safety net for that
-- re-implementation: every RPC is exercised on its happy path AND probed with
-- an unauthorized / self-dealing caller, which must raise (SQLSTATE P0001).
--
-- raise exception '...' produces SQLSTATE P0001; we assert on that code.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(33);

-- ---- Shared fixtures (owner context) -----------------------------------------
select tests.clear_authentication();
select tests.create_scholar('rpc_minter@test.local') as minter \gset
select tests.create_scholar('rpc_admin@test.local') as admin \gset
select tests.create_scholar('rpc_alice@test.local') as alice \gset
select tests.create_scholar('rpc_bob@test.local') as bob \gset
select tests.create_scholar('rpc_outsider@test.local') as outsider \gset
select tests.create_scholar('rpc_steward@test.local', true) as steward \gset

-- Currency minted by :minter; venue administered by :admin (disjoint from the
-- minter, so the no_minter_admins trigger does not fire). Welcome grant of 5.
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[], 5) as ven \gset

--------------------------------------------------------------------------------
-- mint_tokens
--------------------------------------------------------------------------------
-- Happy: a minter mints 3 tokens into the venue reserve.
select tests.authenticate_as(:'minter');
select lives_ok(
	$$ select public.mint_tokens( $$ || quote_literal(:'cur') || $$, 3, $$
		|| quote_literal(:'ven') || $$, 'mint test' ) $$,
	'a minter can mint tokens'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.tokens where venue = :'ven' and currency = :'cur'),
	3,
	'mint_tokens created 3 venue-owned tokens'
);
select is(
	(select count(*)::int from public.transactions
		where to_venue = :'ven' and currency = :'cur' and status = 'approved'),
	1,
	'mint_tokens recorded one approved mint transaction'
);

-- Unauthorized: a non-minter cannot mint.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ select public.mint_tokens( $$ || quote_literal(:'cur') || $$, 1, $$
		|| quote_literal(:'ven') || $$, 'bad mint' ) $$,
	'P0001', null,
	'a non-minter cannot mint tokens'
);

--------------------------------------------------------------------------------
-- transfer_tokens
--------------------------------------------------------------------------------
-- Give :alice four scholar-owned tokens to spend.
select tests.clear_authentication();
insert into public.tokens (currency, scholar) select :'cur', :'alice' from generate_series(1, 4);

-- Happy: a scholar gifts two of their own tokens to :bob.
select tests.authenticate_as(:'alice');
select lives_ok(
	$$ select public.transfer_tokens( $$ || quote_literal(:'cur') || $$, $$
		|| quote_literal(:'alice') || $$, 'scholarid', $$
		|| quote_literal(:'bob') || $$, 'scholarid', 2, 'gift', null ) $$,
	'a scholar can transfer their own tokens'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.tokens where scholar = :'bob' and currency = :'cur'),
	2,
	'transfer_tokens moved two tokens to the recipient scholar'
);

-- Happy: a venue admin moves a venue token to a scholar.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ select public.transfer_tokens( $$ || quote_literal(:'cur') || $$, $$
		|| quote_literal(:'ven') || $$, 'venueid', $$
		|| quote_literal(:'alice') || $$, 'scholarid', 1, 'payout', null ) $$,
	'a venue admin can transfer venue tokens'
);

-- Unauthorized: an outsider cannot move the venue's tokens.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ select public.transfer_tokens( $$ || quote_literal(:'cur') || $$, $$
		|| quote_literal(:'ven') || $$, 'venueid', $$
		|| quote_literal(:'outsider') || $$, 'scholarid', 1, 'theft', null ) $$,
	'P0001', null,
	'an outsider cannot transfer venue tokens'
);

-- Self-dealing: a venue admin cannot transfer venue tokens to themselves.
select tests.authenticate_as(:'admin');
select throws_ok(
	$$ select public.transfer_tokens( $$ || quote_literal(:'cur') || $$, $$
		|| quote_literal(:'ven') || $$, 'venueid', $$
		|| quote_literal(:'admin') || $$, 'scholarid', 1, 'self', null ) $$,
	'P0001', null,
	'a venue admin cannot transfer venue tokens to themselves'
);

--------------------------------------------------------------------------------
-- approve_transaction
--------------------------------------------------------------------------------
-- Pure mint: a proposed mint (no source, placeholder tokens, venue recipient)
-- approved by a minter.
select tests.clear_authentication();
insert into public.transactions (creator, from_scholar, from_venue, to_scholar, to_venue, tokens, currency, purpose, status)
values (:'minter', null, null, null, :'ven',
	array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[2]), :'cur', 'proposed mint', 'proposed')
returning id as mint_txn \gset
select tests.authenticate_as(:'minter');
select lives_ok(
	$$ select public.approve_transaction( $$ || quote_literal(:'mint_txn') || $$ ) $$,
	'a minter can approve a proposed mint'
);
select tests.clear_authentication();
select is(
	(select status::text from public.transactions where id = :'mint_txn'),
	'approved',
	'approve_transaction marked the mint approved'
);
-- An already-approved transaction cannot be approved again (RR001 -> the app's
-- AlreadyApproved message).
select tests.authenticate_as(:'minter');
select throws_ok(
	$$ select public.approve_transaction( $$ || quote_literal(:'mint_txn') || $$ ) $$,
	'RR001', null,
	'a transaction cannot be approved twice'
);

-- Scholar payment: a proposed scholar->venue payment approved by that scholar.
select tests.clear_authentication();
insert into public.transactions (creator, from_scholar, from_venue, to_scholar, to_venue, tokens, currency, purpose, status)
values (:'alice', :'alice', null, null, :'ven',
	array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[1]), :'cur', 'proposed pay', 'proposed')
returning id as pay_txn \gset
select tests.authenticate_as(:'alice');
select lives_ok(
	$$ select public.approve_transaction( $$ || quote_literal(:'pay_txn') || $$ ) $$,
	'a scholar can approve their own proposed payment'
);

-- Self-dealing: the recipient of a venue->scholar transfer cannot approve it.
select tests.clear_authentication();
insert into public.transactions (creator, from_scholar, from_venue, to_scholar, to_venue, tokens, currency, purpose, status)
values (:'admin', null, :'ven', :'bob', null,
	array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[1]), :'cur', 'proposed payout', 'proposed')
returning id as payout_txn \gset
select tests.authenticate_as(:'bob');
select throws_ok(
	$$ select public.approve_transaction( $$ || quote_literal(:'payout_txn') || $$ ) $$,
	'RR002', null,
	'the recipient cannot approve a transaction that pays them'
);

-- Unauthorized: an outsider cannot approve a venue->scholar transfer.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ select public.approve_transaction( $$ || quote_literal(:'payout_txn') || $$ ) $$,
	'P0001', null,
	'an outsider cannot approve a venue transfer'
);

--------------------------------------------------------------------------------
-- create_submission
--------------------------------------------------------------------------------
select tests.clear_authentication();
select tests.create_submission_type(:'ven') as stype \gset
-- Ensure :alice can cover a charge of 1 (she has tokens from earlier transfers).
insert into public.tokens (currency, scholar) select :'cur', :'alice' from generate_series(1, 3);

-- Happy: an author submits and pays their own charge.
select tests.authenticate_as(:'alice');
select lives_ok(
	$$ select public.create_submission( $$ || quote_literal(:'ven') || $$, 'EXT-1', null, null, $$
		|| quote_literal(:'stype') || $$, array[ $$ || quote_literal(:'alice') || $$ ]::uuid[],
		array[1]::integer[], 'A title', 'expertise', null, 'Payment for EXT-1' ) $$,
	'an author can create a submission and pay their own charge'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.submissions where venue = :'ven' and externalid = 'EXT-1'),
	1,
	'create_submission inserted the submission'
);

-- Atomicity: an author who cannot cover their charge gets nothing — the whole
-- operation rolls back (no submission, no dangling proposed transaction).
select tests.authenticate_as(:'bob');
select throws_ok(
	$$ select public.create_submission( $$ || quote_literal(:'ven') || $$, 'EXT-2', null, null, $$
		|| quote_literal(:'stype') || $$, array[ $$ || quote_literal(:'bob') || $$ ]::uuid[],
		array[999]::integer[], 'B title', 'expertise', null, 'Payment for EXT-2' ) $$,
	'RR003', null,
	'a submission whose author cannot pay is rejected'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.submissions where venue = :'ven' and externalid = 'EXT-2'),
	0,
	'the rejected submission left no partial state'
);

--------------------------------------------------------------------------------
-- create_volunteer
--------------------------------------------------------------------------------
select tests.clear_authentication();
-- An invite-only role and an open (self-volunteer) role.
select tests.create_role(:'ven', 1, null, false, true) as invite_role \gset
select tests.create_role(:'ven', 1, null, false, false) as open_role \gset

-- Happy: an admin adds :alice to the invite-only role, with compensation. As
-- her first role this records a proposed welcome grant.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ select public.create_volunteer( $$ || quote_literal(:'alice') || $$, $$
		|| quote_literal(:'invite_role') || $$, false, true, null ) $$,
	'an admin can invite a scholar to a role'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.volunteers where scholarid = :'alice' and roleid = :'invite_role'),
	1,
	'create_volunteer created the volunteer record'
);
select is(
	(select count(*)::int from public.transactions
		where from_venue = :'ven' and to_scholar = :'alice' and status = 'proposed'),
	1,
	'create_volunteer recorded the proposed welcome grant atomically'
);

-- Volunteering for the same role twice is rejected (RR004 -> the app's
-- AlreadyVolunteered message).
select tests.authenticate_as(:'admin');
select throws_ok(
	$$ select public.create_volunteer( $$ || quote_literal(:'alice') || $$, $$
		|| quote_literal(:'invite_role') || $$, false, false, null ) $$,
	'RR004', null,
	'a scholar cannot volunteer for the same role twice'
);

-- Unauthorized: an outsider cannot add someone else to an invite-only role.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ select public.create_volunteer( $$ || quote_literal(:'bob') || $$, $$
		|| quote_literal(:'invite_role') || $$, false, false, null ) $$,
	'P0001', null,
	'an outsider cannot invite others to an invite-only role'
);

-- Allowed: a scholar may add themselves to an open (non-invite-only) role.
select tests.authenticate_as(:'bob');
select lives_ok(
	$$ select public.create_volunteer( $$ || quote_literal(:'bob') || $$, $$
		|| quote_literal(:'open_role') || $$, true, false, null ) $$,
	'a scholar can self-volunteer for an open role'
);

--------------------------------------------------------------------------------
-- accept_role_invite
--------------------------------------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('rpc_invitee@test.local') as invitee \gset
select tests.create_volunteer(:'invitee', :'invite_role', 'invited') as invite \gset

-- Unauthorized: another scholar cannot respond to someone else's invite.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ select public.accept_role_invite( $$ || quote_literal(:'invite') || $$, 'accepted' ) $$,
	'P0001', null,
	'a scholar cannot respond to another scholar''s invitation'
);

-- Happy: the invited scholar accepts.
select tests.authenticate_as(:'invitee');
select lives_ok(
	$$ select public.accept_role_invite( $$ || quote_literal(:'invite') || $$, 'accepted' ) $$,
	'the invited scholar can accept their invitation'
);
select tests.clear_authentication();
select is(
	(select accepted::text from public.volunteers where id = :'invite'),
	'accepted',
	'accept_role_invite recorded the acceptance'
);

--------------------------------------------------------------------------------
-- approve_venue_proposal
--------------------------------------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('rpc_editor@test.local') as editor \gset
insert into public.proposals (title, url, editors, minters, currency, census, payment_free)
values ('Proposed Venue', 'https://example.org', array['rpc_editor@test.local'],
	array['rpc_minter@test.local'], null, 100, false)
returning id as proposal \gset

-- Unauthorized: a non-steward cannot approve a proposal.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ select public.approve_venue_proposal( $$ || quote_literal(:'proposal') || $$ ) $$,
	'P0001', null,
	'a non-steward cannot approve a venue proposal'
);

-- Happy: a steward approves; the venue and its scaffolding are provisioned.
select tests.authenticate_as(:'steward');
select lives_ok(
	$$ select public.approve_venue_proposal( $$ || quote_literal(:'proposal') || $$ ) $$,
	'a steward can approve a venue proposal'
);
select tests.clear_authentication();
select isnt(
	(select venue from public.proposals where id = :'proposal'),
	null,
	'approve_venue_proposal linked the proposal to a new venue'
);
select is(
	(select count(*)::int from public.volunteers v
		join public.roles r on r.id = v.roleid
		where r.venueid = (select venue from public.proposals where id = :'proposal')
		  and v.scholarid = :'editor'),
	1,
	'approve_venue_proposal volunteered the editor onto the new venue'
);
select is(
	(select count(*)::int from public.submission_types
		where venue = (select venue from public.proposals where id = :'proposal')),
	1,
	'approve_venue_proposal created the default submission type'
);

select * from finish();
rollback;
