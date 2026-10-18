-- Declining a bid (#195).
--
-- A bid has three states: pending, approved, declined. Declining is optional -- leaving a
-- bid alone is always allowed -- but a decline is an explicit answer to a person, so it
-- always carries a reason. Under test:
--   * public.decline_bid: who may call it (can_approve_assignment, not conflicted), on
--     what (a pending bid only), and with what (a 1-1000 character reason).
--   * enforce_assignment_updates: the decline columns are an approver's, so a bidder
--     cannot clear their own decline; approving a declined bid clears it.
--   * the DELETE policy: a declined bid cannot be deleted by its bidder.
--   * the open-review SELECT branch: authors see who is assigned, not who bid.
--   * venue decline reasons (#218): a chosen reason is copied onto the bid with its id,
--     must be the venue's own, excludes a written one, and outlives edits to and deletion
--     of the reason.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(29);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('bd_minter@test.local') as minter \gset
select tests.create_scholar('bd_admin@test.local') as admin \gset
select tests.create_scholar('bd_approver@test.local') as approver \gset
select tests.create_scholar('bd_conflicted@test.local') as conflicted \gset
select tests.create_scholar('bd_bidder@test.local') as bidder \gset
select tests.create_scholar('bd_author@test.local') as author \gset
select tests.create_scholar('bd_outsider@test.local') as outsider \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[], 0, false) as ven \gset

select tests.create_role(:'ven', 0, null, false, false) as roleapprover \gset
select tests.create_role(:'ven', 1, :'roleapprover', true, false) as rolechild \gset

select tests.create_volunteer(:'bidder', :'rolechild', 'accepted') as v_bidder \gset

select tests.create_submission_type(:'ven') as stype \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as sub \gset

-- The approver and the conflicted viewer both hold the approving role on the submission,
-- so the only difference between them is the conflict.
select tests.create_assignment(:'ven', :'sub', :'approver', :'roleapprover', true, false) as asg_approver \gset
select tests.create_assignment(:'ven', :'sub', :'conflicted', :'roleapprover', true, false) as asg_conflicted \gset
insert into public.conflicts (submissionid, scholarid) values (:'sub', :'conflicted');

-- The bid under test, pending.
select tests.create_assignment(:'ven', :'sub', :'bidder', :'rolechild', false, true) as bid \gset

-- Two more bids, declined with one of the venue's reasons.
select tests.create_scholar('bd_bidder2@test.local') as bidder2 \gset
select tests.create_scholar('bd_bidder3@test.local') as bidder3 \gset
select tests.create_volunteer(:'bidder2', :'rolechild', 'accepted') as v_bidder2 \gset
select tests.create_volunteer(:'bidder3', :'rolechild', 'accepted') as v_bidder3 \gset
select tests.create_assignment(:'ven', :'sub', :'bidder2', :'rolechild', false, true) as bid2 \gset
select tests.create_assignment(:'ven', :'sub', :'bidder3', :'rolechild', false, true) as bid3 \gset

-- The venue's own default reason, and another venue's.
select id as reason from public.decline_reasons where venueid = :'ven' and rank = 1 \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as otherven \gset
select id as otherreason from public.decline_reasons where venueid = :'otherven' and rank = 0 \gset

-- ---- Open review hides bids from authors ---------------------------------------
-- The venue is open review, so the author may see who is assigned...
select tests.authenticate_as(:'author');
select isnt_empty(
	$$ select 1 from public.assignments where id = $$ || quote_literal(:'asg_approver'),
	'in open review, an author sees approved assignments'
);

-- ...but not who bid, and so never a decline reason.
select is_empty(
	$$ select 1 from public.assignments where id = $$ || quote_literal(:'bid'),
	'in open review, an author does not see pending bids'
);

-- ---- Who may decline -----------------------------------------------------------
select tests.authenticate_as(:'bidder');
select throws_ok(
	$$ select public.decline_bid($$ || quote_literal(:'bid') || $$, 'no thanks') $$,
	'P0001',
	'You are not authorized to decline this bid',
	'a bidder cannot decline their own bid'
);

select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ select public.decline_bid($$ || quote_literal(:'bid') || $$, 'no thanks') $$,
	'P0001',
	'You are not authorized to decline this bid',
	'an unrelated scholar cannot decline a bid'
);

select tests.authenticate_as(:'conflicted');
select throws_ok(
	$$ select public.decline_bid($$ || quote_literal(:'bid') || $$, 'no thanks') $$,
	'P0001',
	'You are not authorized to decline this bid',
	'a conflicted approver cannot decline a bid'
);

select tests.authenticate_as_anon();
select throws_ok(
	$$ select public.decline_bid($$ || quote_literal(:'bid') || $$, 'no thanks') $$,
	'42501',
	null,
	'an anonymous visitor cannot call decline_bid'
);

-- ---- What a decline needs ------------------------------------------------------
select tests.authenticate_as(:'approver');
select throws_ok(
	$$ select public.decline_bid($$ || quote_literal(:'bid') || $$, '   ') $$,
	'P0001',
	'A declined bid needs an explanation for the bidder',
	'a decline without a reason is refused'
);

select throws_ok(
	$$ select public.decline_bid($$ || quote_literal(:'bid') || $$, repeat('x', 1001)) $$,
	'P0001',
	'An explanation must be at most 1000 characters',
	'a reason over 1000 characters is refused'
);

-- Declining directly, around the RPC, is refused to someone who cannot approve.
select tests.authenticate_as(:'bidder');
select throws_ok(
	$$ update public.assignments set declined_at = now(), decline_reason = 'x' where id = $$ || quote_literal(:'bid'),
	'RR018',
	null,
	'a bidder cannot write the decline columns directly'
);

-- ---- Declining -----------------------------------------------------------------
select tests.authenticate_as(:'approver');
select lives_ok(
	$$ select public.decline_bid($$ || quote_literal(:'bid') || $$, '  Your expertise is in a different area.  ') $$,
	'an approver seated on the submission can decline a bid'
);

select tests.clear_authentication();
select results_eq(
	$$ select declined_by, decline_reason, declined_at is not null from public.assignments where id = $$ || quote_literal(:'bid'),
	$$ values ($$ || quote_literal(:'approver') || $$::uuid, 'Your expertise is in a different area.', true) $$,
	'the decline records who declined, the trimmed reason, and when'
);

-- Answering twice is refused: the race two approvers would otherwise both win.
select tests.authenticate_as(:'admin');
select throws_ok(
	$$ select public.decline_bid($$ || quote_literal(:'bid') || $$, 'again') $$,
	'RR017',
	null,
	'an already-declined bid cannot be declined again'
);

-- ---- The bidder after a decline ------------------------------------------------
select tests.authenticate_as(:'bidder');
select results_eq(
	$$ select decline_reason from public.assignments where id = $$ || quote_literal(:'bid'),
	$$ values ('Your expertise is in a different area.') $$,
	'the bidder can read the reason they were given'
);

select throws_ok(
	$$ update public.assignments set declined_at = null, declined_by = null, decline_reason = null where id = $$ || quote_literal(:'bid'),
	'RR018',
	null,
	'the bidder cannot clear the decline'
);

-- The DELETE policy filters the row rather than erroring.
delete from public.assignments where id = :'bid';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.assignments where id = :'bid'),
	1,
	'the bidder cannot delete a declined bid, and so cannot bid afresh'
);

-- The author still cannot see it in open review.
select tests.authenticate_as(:'author');
select is_empty(
	$$ select 1 from public.assignments where id = $$ || quote_literal(:'bid'),
	'in open review, an author does not see declined bids'
);

-- ---- Changing one's mind -------------------------------------------------------
select tests.authenticate_as(:'approver');
select lives_ok(
	$$ update public.assignments set approved = true where id = $$ || quote_literal(:'bid'),
	'an approver can approve a declined bid after all'
);

select tests.clear_authentication();
select results_eq(
	$$ select approved, declined_at is null, declined_by is null, decline_reason is null from public.assignments where id = $$ || quote_literal(:'bid'),
	$$ values (true, true, true, true) $$,
	'approving a declined bid clears the decline'
);

-- An approved assignment is not a pending bid.
select tests.authenticate_as(:'approver');
select throws_ok(
	$$ select public.decline_bid($$ || quote_literal(:'bid') || $$, 'changed my mind') $$,
	'RR017',
	null,
	'an approved bid cannot be declined'
);

-- ---- Declining with a venue reason (#218) --------------------------------------
select ok(
	not has_function_privilege('anon', 'public.decline_bid(uuid,text,uuid)', 'execute'),
	'an anonymous visitor cannot execute decline_bid'
);

select tests.authenticate_as(:'approver');
select throws_ok(
	format($$ select public.decline_bid(%L, null, %L) $$, :'bid2', :'otherreason'),
	'P0001',
	'That decline reason does not belong to this venue',
	'another venue''s reason is refused'
);

select throws_ok(
	format($$ select public.decline_bid(%L, 'and my own words', %L) $$, :'bid2', :'reason'),
	'P0001',
	'A decline gives the venue''s reason or the approver''s own, not both',
	'a venue reason cannot be combined with the approver''s own words'
);

select lives_ok(
	format($$ select public.decline_bid(%L, '', %L) $$, :'bid2', :'reason'),
	'an approver can decline with one of the venue''s reasons'
);

select tests.clear_authentication();
select results_eq(
	format($$ select decline_reason, decline_reason_id from public.assignments where id = %L $$, :'bid2'),
	format($$ values ('We selected a different scholar.', %L::uuid) $$, :'reason'),
	'the reason''s text is copied onto the bid, with its id'
);

select tests.authenticate_as(:'approver');
select lives_ok(
	format($$ select public.decline_bid(%L, 'Your work is outside this area.') $$, :'bid3'),
	'an approver can still write their own reason'
);

select tests.clear_authentication();
select results_eq(
	format($$ select decline_reason, decline_reason_id is null from public.assignments where id = %L $$, :'bid3'),
	$$ values ('Your work is outside this area.', true) $$,
	'a written reason is stored with no venue reason'
);

-- Editing, then deleting, the reason never rewrites what the bidder was told.
update public.decline_reasons set text = 'We chose someone else.' where id = :'reason';
delete from public.decline_reasons where id = :'reason';
select results_eq(
	format($$ select decline_reason, decline_reason_id is null from public.assignments where id = %L $$, :'bid2'),
	$$ values ('We selected a different scholar.', true) $$,
	'a deleted reason leaves the decline''s words in place'
);

-- Approving after all clears every decline column.
select tests.authenticate_as(:'approver');
select lives_ok(
	format($$ update public.assignments set approved = true where id = %L $$, :'bid3'),
	'an approver can approve a bid declined after all'
);

select tests.clear_authentication();
select results_eq(
	format($$ select decline_reason is null, decline_reason_id is null from public.assignments where id = %L $$, :'bid3'),
	$$ values (true, true) $$,
	'approving clears the reason and its id'
);

select * from finish();
rollback;
