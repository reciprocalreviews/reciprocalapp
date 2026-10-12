-- Bid budgets and the rules on placing a bid (public.enforce_bid_rules).
--
-- A volunteer's budget for a role is the role's percent of the venue's submissions
-- under review, never below the role's floor, and at most three times the papers the
-- volunteer said they would review. Every bid on a submission under review counts --
-- pending, approved or declined. Bids already placed are never removed; a scholar over
-- budget just cannot bid again. Under test:
--   * the floor, the percent, the papers cap, and turning the budget off
--   * done submissions give their bids back; declined and approved bids do not
--   * RR026 for a role that is not biddable, a done submission, a second bid, a full role
--   * whoever may approve the assignment is exempt
--   * who may read a budget

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('bb_minter@test.local') as minter \gset
select tests.create_scholar('bb_admin@test.local') as admin \gset
select tests.create_scholar('bb_bidder@test.local') as bidder \gset
select tests.create_scholar('bb_other@test.local') as other \gset
select tests.create_scholar('bb_author@test.local') as author \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

select tests.create_role(:'ven', 0, null, false, false) as editor \gset
select tests.create_role(:'ven', 1, :'editor', true, false) as reviewer \gset
select tests.create_role(:'ven', 2, :'editor', false, false) as unbiddable \gset

select tests.create_volunteer(:'bidder', :'reviewer', 'accepted') as v_bidder \gset
select tests.create_volunteer(:'bidder', :'unbiddable', 'accepted') as v_unbiddable \gset

-- Twelve submissions under review. With a floor of 3 and 10%, the limit is
-- max(3, ceil(1.2)) = 3.
update public.roles set bid_limit_floor = 3, bid_limit_percent = 10 where id = :'reviewer';

select tests.create_submission_type(:'ven') as stype \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s1 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s2 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s3 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s4 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s5 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s6 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s7 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s8 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s9 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s10 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s11 \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s12 \gset

-- Place a bid as whoever is authenticated.
create function tests.bid (p_venue uuid, p_submission uuid, p_scholar uuid, p_role uuid)
returns void language sql as $$
	insert into public.assignments (venue, submission, scholar, role, bid)
	values (p_venue, p_submission, p_scholar, p_role, true);
$$;

-- ---- The floor -----------------------------------------------------------------
select tests.authenticate_as(:'bidder');
select lives_ok(
	format('select tests.bid(%L, %L, %L, %L)', :'ven', :'s1', :'bidder', :'reviewer'),
	'a first bid fits the budget'
);
select lives_ok(
	format('select tests.bid(%L, %L, %L, %L); select tests.bid(%L, %L, %L, %L)',
		:'ven', :'s2', :'bidder', :'reviewer', :'ven', :'s3', :'bidder', :'reviewer'),
	'bids up to the floor fit the budget'
);
select results_eq(
	format('select used, bid_limit from public.my_bid_budget(%L)', :'reviewer'),
	$$ values (3, 3) $$,
	'my_bid_budget reports three of three used'
);
select throws_ok(
	format('select tests.bid(%L, %L, %L, %L)', :'ven', :'s4', :'bidder', :'reviewer'),
	'RR025',
	null,
	'a bid past the floor is refused when the percent is lower'
);

-- ---- The percent ---------------------------------------------------------------
-- 50% of twelve is six.
select tests.clear_authentication();
update public.roles set bid_limit_percent = 50 where id = :'reviewer';
select tests.authenticate_as(:'bidder');
select results_eq(
	format('select bid_limit from public.my_bid_budget(%L)', :'reviewer'),
	$$ values (6) $$,
	'the percent sets the limit once it exceeds the floor'
);
select lives_ok(
	format('select tests.bid(%L, %L, %L, %L)', :'ven', :'s4', :'bidder', :'reviewer'),
	'a bid within the percent fits'
);

-- ---- Over budget already -------------------------------------------------------
-- Back to a limit of 3 with four bids placed: the bids stay, and no more may be placed.
select tests.clear_authentication();
update public.roles set bid_limit_percent = 10 where id = :'reviewer';
select tests.authenticate_as(:'bidder');
select results_eq(
	format('select count(*)::integer from public.assignments where scholar = %L and role = %L', :'bidder', :'reviewer'),
	$$ values (4) $$,
	'lowering the limit leaves bids already placed'
);
select throws_ok(
	format('select tests.bid(%L, %L, %L, %L)', :'ven', :'s5', :'bidder', :'reviewer'),
	'RR025',
	null,
	'a scholar over budget cannot bid again'
);

-- ---- Done submissions give their bids back ------------------------------------
-- Two done: ten under review, limit max(3, 1) = 3, two bids still count.
select tests.clear_authentication();
update public.submissions set status = 'done' where id in (:'s1', :'s2');
select tests.authenticate_as(:'bidder');
select results_eq(
	format('select used, bid_limit from public.my_bid_budget(%L)', :'reviewer'),
	$$ values (2, 3) $$,
	'bids on done submissions do not count'
);
select lives_ok(
	format('select tests.bid(%L, %L, %L, %L)', :'ven', :'s5', :'bidder', :'reviewer'),
	'a done submission frees room for another bid'
);

-- ---- Declined and approved bids still count -----------------------------------
select tests.clear_authentication();
update public.assignments
set declined_at = now(), declined_by = :'admin', decline_reason = 'Not a fit'
where scholar = :'bidder' and submission = :'s5';
update public.assignments set approved = true where scholar = :'bidder' and submission = :'s3';
select tests.authenticate_as(:'bidder');
select results_eq(
	format('select used from public.my_bid_budget(%L)', :'reviewer'),
	$$ values (3) $$,
	'declined and approved bids still count against the budget'
);
select throws_ok(
	format('select tests.bid(%L, %L, %L, %L)', :'ven', :'s6', :'bidder', :'reviewer'),
	'RR025',
	null,
	'a declined bid does not free room for another'
);

-- ---- The papers cap ------------------------------------------------------------
-- 100% of ten is ten, but one paper caps bids at three.
select tests.clear_authentication();
update public.roles set bid_limit_percent = 100 where id = :'reviewer';
update public.volunteers set papers = 1 where id = :'v_bidder';
select tests.authenticate_as(:'bidder');
select results_eq(
	format('select bid_limit from public.my_bid_budget(%L)', :'reviewer'),
	$$ values (3) $$,
	'a volunteer''s papers cap limits bids to three times it'
);
select tests.clear_authentication();
update public.volunteers set papers = null where id = :'v_bidder';
select tests.authenticate_as(:'bidder');
select lives_ok(
	format('select tests.bid(%L, %L, %L, %L)', :'ven', :'s6', :'bidder', :'reviewer'),
	'without a papers cap, the percent alone decides'
);

-- ---- Turning the budget off ----------------------------------------------------
select tests.clear_authentication();
update public.roles set bid_limit_percent = null where id = :'reviewer';
select tests.authenticate_as(:'bidder');
select results_eq(
	format('select bid_limit from public.my_bid_budget(%L)', :'reviewer'),
	$$ values (null::integer) $$,
	'a role without a percent has no budget'
);
select lives_ok(
	format('select tests.bid(%L, %L, %L, %L); select tests.bid(%L, %L, %L, %L)',
		:'ven', :'s7', :'bidder', :'reviewer', :'ven', :'s8', :'bidder', :'reviewer'),
	'a role without a budget takes any number of bids'
);

-- ---- RR026: bids the submissions page never offered ---------------------------
select throws_ok(
	format('select tests.bid(%L, %L, %L, %L)', :'ven', :'s9', :'bidder', :'unbiddable'),
	'RR026',
	null,
	'a volunteer cannot bid on a role that is not biddable'
);
select throws_ok(
	format('select tests.bid(%L, %L, %L, %L)', :'ven', :'s1', :'bidder', :'reviewer'),
	'RR026',
	null,
	'a volunteer cannot bid on a done submission'
);
select throws_ok(
	format('select tests.bid(%L, %L, %L, %L)', :'ven', :'s7', :'bidder', :'reviewer'),
	'RR026',
	null,
	'a volunteer cannot bid twice on one submission in one role'
);
select tests.clear_authentication();
select tests.create_assignment(:'ven', :'s9', :'other', :'reviewer', true, false) as seated \gset
select tests.authenticate_as(:'bidder');
select throws_ok(
	format('select tests.bid(%L, %L, %L, %L)', :'ven', :'s9', :'bidder', :'reviewer'),
	'RR026',
	null,
	'a volunteer cannot bid on a role already full on the submission'
);

-- ---- Approvers are exempt ------------------------------------------------------
select tests.authenticate_as(:'admin');
select lives_ok(
	format('select tests.bid(%L, %L, %L, %L)', :'ven', :'s10', :'admin', :'unbiddable'),
	'whoever may approve the assignment is not held to the bid rules'
);

-- ---- Who may read a budget -----------------------------------------------------
select tests.authenticate_as(:'other');
select results_eq(
	format('select used from public.my_bid_budget(%L)', :'reviewer'),
	$$ values (0) $$,
	'my_bid_budget answers only for the caller'
);
select tests.clear_authentication();
select ok(
	not has_function_privilege('authenticated', 'public._bid_limit(uuid, uuid)', 'execute'),
	'a client cannot read another scholar''s budget through _bid_limit'
);
select ok(
	not has_function_privilege('anon', 'public.my_bid_budget(uuid)', 'execute'),
	'anon cannot call my_bid_budget'
);

select * from finish();

rollback;
