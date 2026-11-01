-- RPC tests for public.close_submission: an editor settling every outstanding assignment on
-- a submission -- paying the ones whose work was done, removing the rest -- and marking it
-- done, in one step.
--
-- What is under test:
--   WHO      only an approved priority-0 editor on the submission; a reviewer on it may not.
--   WHAT     _pay and _remove must together be exactly the outstanding assignments, with no
--            overlap, so a stale page cannot close over an assignment it never showed.
--   MONEY    a short reserve pays nobody and proposes one mint for the whole shortfall,
--            reviewers and editors together; otherwise each _pay is paid, each _remove is
--            deleted, the editor is paid, and the submission is done.
--
-- The send_on_email_insert trigger is disabled for this rolled-back test: nothing here
-- depends on mail being dispatched.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan (13);

alter table public.emails disable trigger send_on_email_insert;

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('cs_minter@test.local') as minter \gset
select tests.create_scholar('cs_admin@test.local')  as admin  \gset
select tests.create_scholar('cs_editor@test.local') as editor \gset
select tests.create_scholar('cs_done@test.local')   as did    \gset
select tests.create_scholar('cs_ghost@test.local')  as ghost  \gset
select tests.create_scholar('cs_author@test.local') as author \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

select tests.create_role(:'ven', 0) as edrole  \gset
select tests.create_role(:'ven', 1) as revrole \gset
select tests.create_submission_type(:'ven') as stype \gset

-- Editors are paid 1, reviewers 10.
insert into public.compensation (submission_type, role, amount)
values (:'stype', :'edrole', 1), (:'stype', :'revrole', 10)
on conflict (submission_type, role) do update set amount = excluded.amount;

select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as sub \gset
select tests.create_assignment(:'ven', :'sub', :'editor', :'edrole') as aeditor \gset
select tests.create_assignment(:'ven', :'sub', :'did', :'revrole')   as adid    \gset
select tests.create_assignment(:'ven', :'sub', :'ghost', :'revrole') as aghost  \gset

-- 5 tokens in reserve: short of the 21 paying both reviewers and the editor would take, and
-- of the 11 paying one -- but enough for either payment alone, which is the point: a close
-- that paid as it went would pay somebody before discovering it could not finish.
insert into public.tokens (currency, venue) select :'cur', :'ven' from generate_series(1, 5);

-- ---- Who may not ---------------------------------------------------------------
select tests.authenticate_as(:'did');
select throws_ok(
	format(
		'select public.close_submission(%L, array[%L, %L]::uuid[], ''{}''::uuid[], '''', '''')',
		:'sub', :'adid', :'aghost'
	),
	'Only an approved editor (priority-0) can close this submission',
	'a reviewer on the submission cannot close it'
);

-- ---- The choices must be exactly the outstanding assignments -------------------
select tests.authenticate_as(:'editor');
select throws_ok(
	format(
		'select public.close_submission(%L, array[%L]::uuid[], ''{}''::uuid[], '''', '''')',
		:'sub', :'adid'
	),
	'The assignments to pay and remove must be exactly the outstanding ones; reload and try again',
	'a close that leaves an outstanding assignment out is refused'
);
select throws_ok(
	format(
		'select public.close_submission(%L, array[%L, %L]::uuid[], array[%L]::uuid[], '''', '''')',
		:'sub', :'adid', :'aghost', :'aghost'
	),
	'An assignment cannot be both paid and removed',
	'an assignment named both to pay and to remove is refused'
);
select throws_ok(
	format(
		'select public.close_submission(%L, array[%L, %L, %L]::uuid[], ''{}''::uuid[], '''', '''')',
		:'sub', :'adid', :'aghost', :'aeditor'
	),
	'The assignments to pay and remove must be exactly the outstanding ones; reload and try again',
	'the editor''s own assignment is not one of the choices'
);

-- ---- A short reserve pays nobody -----------------------------------------------
select is(
	(public.close_submission(:'sub', array[:'adid']::uuid[], array[:'aghost']::uuid[], 'pay', 'mint {shortfall}'))->>'status',
	'insufficient',
	'a close the reserve cannot cover reports insufficient'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.transactions
		where to_venue = :'ven' and status = 'proposed' and cardinality(tokens) = 6),
	1,
	'one mint is proposed for the whole shortfall: 10 for the reviewer and 1 for the editor, less 5'
);
select is(
	(select count(*)::int from public.assignments
		where submission = :'sub' and (completed or id = :'aghost')),
	1,
	'nothing was paid and nothing removed: only the removal candidate is still there, uncompleted'
);

-- ---- Success -------------------------------------------------------------------
insert into public.tokens (currency, venue) select :'cur', :'ven' from generate_series(1, 6);

select tests.authenticate_as(:'editor');
select public.close_submission(:'sub', array[:'adid']::uuid[], array[:'aghost']::uuid[], 'pay', 'mint') as closed \gset
select is(
	(:'closed'::jsonb)->>'status',
	'completed',
	'with the reserve topped up, the close completes'
);
-- The caller emails whoever was removed, so the RPC must say who that was.
select is(
	(:'closed'::jsonb)->'removed'->0->>'scholar_id',
	:'ghost',
	'the close reports the removed reviewer, so they can be told'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.tokens where scholar = :'did' and currency = :'cur'),
	10,
	'the reviewer whose work was done is paid'
);
select is(
	(select count(*)::int from public.assignments where id = :'aghost'),
	0,
	'the reviewer whose work was not done is removed'
);
select is(
	(select count(*)::int from public.tokens where scholar = :'editor' and currency = :'cur'),
	1,
	'the editor is paid'
);
select is(
	(select status::text from public.submissions where id = :'sub'),
	'done',
	'the submission is done'
);

select * from finish();
rollback;
