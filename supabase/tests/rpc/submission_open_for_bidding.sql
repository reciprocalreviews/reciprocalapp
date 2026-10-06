-- Tests for public.set_submission_open_for_bidding: who may open or close bidding on a
-- submission.
--
-- Rule under test: whoever may answer bids on the submission -- can_approve_assignment
-- for some biddable role at its venue. That is a venue admin, the submission's
-- priority-0 editor, or the holder of a bid-approving role seated on THIS submission
-- (an Associate Editor approving Reviewer bids). Not a seated reviewer, not an author,
-- not a stranger, not an Associate Editor seated on some other submission, and not the
-- holder of an approving role whose target role takes no bids.
--
-- The regression this guards: only the priority-0 editor could, so an Associate Editor
-- answering a submission's bids could not close its bidding.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('sob_minter@test.local') as minter \gset
select tests.create_scholar('sob_admin@test.local') as admin \gset
select tests.create_scholar('sob_editor@test.local') as editor \gset
select tests.create_scholar('sob_ae@test.local') as ae \gset
select tests.create_scholar('sob_other_ae@test.local') as other_ae \gset
select tests.create_scholar('sob_reviewer@test.local') as reviewer \gset
select tests.create_scholar('sob_lead@test.local') as lead \gset
select tests.create_scholar('sob_author@test.local') as author \gset
select tests.create_scholar('sob_outsider@test.local') as outsider \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset
select tests.create_submission_type(:'ven') as stype \gset

-- Editor (priority 0); Associate Editor approves Reviewer, which takes bids. Lead
-- approves Proofreader, which does not.
select tests.create_role(:'ven', 0, null, false, false) as editor_role \gset
select tests.create_role(:'ven', 1, :'editor_role', false, false) as ae_role \gset
select tests.create_role(:'ven', 2, :'ae_role', true, false) as reviewer_role \gset
select tests.create_role(:'ven', 3, null, false, false) as lead_role \gset
select tests.create_role(:'ven', 4, :'lead_role', false, false) as proof_role \gset

select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as sub \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as other_sub \gset

select tests.create_assignment(:'ven', :'sub', :'editor', :'editor_role', true, false) as a1 \gset
select tests.create_assignment(:'ven', :'sub', :'ae', :'ae_role', true, false) as a2 \gset
select tests.create_assignment(:'ven', :'sub', :'reviewer', :'reviewer_role', true, false) as a3 \gset
select tests.create_assignment(:'ven', :'sub', :'lead', :'lead_role', true, false) as a4 \gset
-- An Associate Editor, but of the other submission.
select tests.create_assignment(:'ven', :'other_sub', :'other_ae', :'ae_role', true, false) as a5 \gset

create function pg_temp.closed () returns boolean language sql as $$
	select bidding_closed from public.submissions where id = current_setting('sob.sub')::uuid;
$$;
select set_config('sob.sub', :'sub', true);

-- ---- Who may ------------------------------------------------------------------
select tests.authenticate_as(:'ae');
select lives_ok(
	format('select public.set_submission_open_for_bidding(%L, false)', :'sub'),
	'the Associate Editor seated on the submission can close its bidding'
);
select tests.clear_authentication();
select is(pg_temp.closed (), true, 'and it is closed');

select tests.authenticate_as(:'ae');
select lives_ok(
	format('select public.set_submission_open_for_bidding(%L, true)', :'sub'),
	'and can reopen it'
);
select tests.clear_authentication();
select is(pg_temp.closed (), false, 'and it is open again');

select tests.authenticate_as(:'editor');
select lives_ok(
	format('select public.set_submission_open_for_bidding(%L, false)', :'sub'),
	'the submission''s editor can close its bidding'
);

select tests.authenticate_as(:'admin');
select lives_ok(
	format('select public.set_submission_open_for_bidding(%L, true)', :'sub'),
	'a venue admin can reopen it'
);
select tests.clear_authentication();
select is(pg_temp.closed (), false, 'and the admin''s reopening took effect');

-- ---- Who may not --------------------------------------------------------------
select tests.authenticate_as(:'reviewer');
select throws_ok(
	format('select public.set_submission_open_for_bidding(%L, false)', :'sub'),
	'42501',
	null,
	'a reviewer seated on the submission cannot'
);

select tests.authenticate_as(:'author');
select throws_ok(
	format('select public.set_submission_open_for_bidding(%L, false)', :'sub'),
	'42501',
	null,
	'an author cannot'
);

select tests.authenticate_as(:'outsider');
select throws_ok(
	format('select public.set_submission_open_for_bidding(%L, false)', :'sub'),
	'42501',
	null,
	'a stranger cannot'
);

select tests.authenticate_as(:'other_ae');
select throws_ok(
	format('select public.set_submission_open_for_bidding(%L, false)', :'sub'),
	'42501',
	null,
	'an Associate Editor seated on a different submission cannot'
);

select tests.authenticate_as(:'lead');
select throws_ok(
	format('select public.set_submission_open_for_bidding(%L, false)', :'sub'),
	'42501',
	null,
	'approving a role that takes no bids is not enough'
);

select tests.clear_authentication();
select is(pg_temp.closed (), false, 'none of the refusals changed anything');

select ok(
	not has_function_privilege('anon', 'public.set_submission_open_for_bidding(uuid,boolean)', 'execute'),
	'anon cannot call it'
);

select * from finish();
rollback;
