-- Assigning from a list: public.assign_submissions seats people in one role on submissions
-- the venue already has.
--
-- Under test:
--   * only the venue's admins and priority-0 editors may call it, and anon cannot reach it;
--   * a dry run gives every line a verdict and writes nothing;
--   * a real run seats the ready lines, keeps unmatched names, and skips the rest;
--   * an existing claim by the person becomes their approved assignment, not a duplicate;
--   * a caller who wrote a submission cannot assign on it.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('as_minter@test.local') as minter \gset
select tests.create_scholar('as_admin@test.local') as admin \gset
select tests.create_scholar('as_ed1@test.local') as ed1 \gset
select tests.create_scholar('as_ed2@test.local') as ed2 \gset
select tests.create_scholar('as_author@test.local') as author \gset
select tests.create_scholar('as_outsider@test.local') as outsider \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset
select tests.create_role(:'ven', 0, null, false, false) as roleeditor \gset
select tests.create_role(:'ven', 1, null, false, false) as rolereviewer \gset
select tests.create_volunteer(:'ed1', :'roleeditor', 'accepted') as v1 \gset
select tests.create_volunteer(:'ed2', :'roleeditor', 'accepted') as v2 \gset
select tests.create_submission_type(:'ven') as stype \gset

-- One submission per verdict, each given a readable manuscript ID.
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_ready \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_keep \gset
select tests.create_submission(:'ven', :'stype', array[:'ed1']::uuid[]) as s_author \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_conflict \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_held \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_done \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_already \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_claim \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_waiting \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_outsider \gset
select tests.create_submission(:'ven', :'stype', array[:'ed2']::uuid[]) as s_ed2 \gset

update public.submissions set externalid = 'M-READY' where id = :'s_ready';
update public.submissions set externalid = 'M-KEEP' where id = :'s_keep';
update public.submissions set externalid = 'M-AUTHOR' where id = :'s_author';
update public.submissions set externalid = 'M-CONFLICT' where id = :'s_conflict';
update public.submissions set externalid = 'M-HELD' where id = :'s_held';
update public.submissions set externalid = 'M-DONE', status = 'done' where id = :'s_done';
update public.submissions set externalid = 'M-ALREADY' where id = :'s_already';
update public.submissions set externalid = 'M-CLAIM' where id = :'s_claim';
update public.submissions set externalid = 'M-WAITING' where id = :'s_waiting';
update public.submissions set externalid = 'M-OUTSIDER' where id = :'s_outsider';
update public.submissions set externalid = 'M-ED2' where id = :'s_ed2';

insert into public.conflicts (submissionid, scholarid) values (:'s_conflict', :'ed1');
select tests.create_assignment(:'ven', :'s_held', :'ed2', :'roleeditor') as held \gset
select tests.create_assignment(:'ven', :'s_already', :'ed1', :'roleeditor') as already \gset
select tests.create_assignment(:'ven', :'s_claim', :'ed1', :'roleeditor', false) as claim \gset
insert into public.unmatched_assignments (venue, submission, role, name)
values (:'ven', :'s_waiting', :'roleeditor', 'Someone Imported');

-- The list: one line per verdict, in this order.
select jsonb_build_array(
	jsonb_build_object('externalid', 'M-READY', 'person', :'ed1'),
	jsonb_build_object('externalid', ' M-KEEP ', 'name', ' Jane Doe '),
	jsonb_build_object('externalid', 'M-AUTHOR', 'person', :'ed1'),
	jsonb_build_object('externalid', 'M-CONFLICT', 'person', :'ed1'),
	jsonb_build_object('externalid', 'M-HELD', 'person', :'ed1'),
	jsonb_build_object('externalid', 'M-DONE', 'person', :'ed1'),
	jsonb_build_object('externalid', 'M-ALREADY', 'person', :'ed1'),
	jsonb_build_object('externalid', 'M-CLAIM', 'person', :'ed1'),
	jsonb_build_object('externalid', 'M-WAITING', 'person', :'ed1'),
	jsonb_build_object('externalid', 'M-OUTSIDER', 'person', :'outsider'),
	jsonb_build_object('externalid', 'M-NOPE', 'person', :'ed1'),
	jsonb_build_object('externalid', 'M-READY', 'person', :'ed2')
) as list \gset

-- ---- Who may call it ----------------------------------------------------------------
select ok(
	not has_function_privilege('anon', 'public.assign_submissions(uuid, uuid, jsonb, boolean)', 'execute'),
	'anon cannot execute assign_submissions'
);

select tests.authenticate_as(:'outsider');
select throws_ok(
	format('select public.assign_submissions(%L, %L, %L::jsonb, true)', :'ven', :'roleeditor', :'list'),
	'42501',
	'Only venue admins and editors can assign from a list',
	'someone who neither administers nor edits the venue is refused'
);

select tests.authenticate_as(:'admin');
select throws_ok(
	format('select public.assign_submissions(%L, %L, %L::jsonb, true)', :'ven', gen_random_uuid(), :'list'),
	'That role does not belong to this venue',
	'a role from elsewhere is refused'
);

-- ---- A dry run is a preview ---------------------------------------------------------
select public.assign_submissions(:'ven', :'roleeditor', :'list', true) as preview \gset

select results_eq(
	format($$ select r->>'verdict' from jsonb_array_elements(%L::jsonb->'rows') with ordinality as t(r, n) order by n $$, :'preview'),
	$$ values ('ready'), ('keep'), ('author'), ('conflicted'), ('held'), ('done'), ('already'),
		('ready'), ('waiting'), ('not_volunteer'), ('missing'), ('duplicate') $$,
	'a dry run gives every line its verdict'
);
select is(
	(:'preview'::jsonb->'rows'->4->>'holder')::uuid, :'ed2'::uuid,
	'a held seat names who holds it'
);
select is((:'preview'::jsonb->>'seated')::int, 0, 'a dry run seats nobody');

select tests.clear_authentication();
select is(
	(select count(*)::int from public.assignments where submission = :'s_ready'), 0,
	'a dry run writes no assignment'
);
select is(
	(select count(*)::int from public.unmatched_assignments where submission = :'s_keep'), 0,
	'a dry run keeps no name'
);

-- ---- A real run ---------------------------------------------------------------------
select tests.authenticate_as(:'admin');
select public.assign_submissions(:'ven', :'roleeditor', :'list', false) as done \gset
select tests.clear_authentication();

select is((:'done'::jsonb->>'seated')::int, 2, 'the ready lines are seated');
select is((:'done'::jsonb->>'kept')::int, 1, 'the unmatched name is kept');
select is((:'done'::jsonb->>'skipped')::int, 9, 'every other line is skipped, not refused');
select is(
	(:'done'::jsonb->'seated_by'->>:'ed1')::int, 2,
	'seated_by counts the submissions each person was given'
);
select is(:'done'::jsonb->'rows'->0->>'verdict', 'seated', 'a seated line says so');

select ok(
	exists (select 1 from public.assignments where submission = :'s_ready' and scholar = :'ed1'
		and role = :'roleeditor' and approved and not bid),
	'the ready line is an approved assignment'
);
select is(
	(select count(*)::int from public.assignments where submission = :'s_ready'), 1,
	'a manuscript named twice is seated once'
);
select results_eq(
	format($$ select name from public.unmatched_assignments where submission = %L $$, :'s_keep'),
	$$ values ('Jane Doe') $$,
	'the kept name is trimmed, and its manuscript ID was found despite surrounding spaces'
);
select results_eq(
	format($$ select approved from public.assignments where submission = %L and scholar = %L $$, :'s_claim', :'ed1'),
	$$ values (true) $$,
	'an existing claim is approved rather than duplicated'
);
select is(
	(select count(*)::int from public.assignments where submission in (:'s_author', :'s_conflict', :'s_done', :'s_waiting', :'s_outsider')),
	0,
	'no skipped line wrote an assignment'
);
select results_eq(
	format($$ select scholar from public.assignments where submission = %L $$, :'s_held'),
	format($$ values (%L::uuid) $$, :'ed2'),
	'a held seat is left to its holder'
);

-- ---- An editor, and their own submission -----------------------------------------------
select tests.authenticate_as(:'ed2');
select public.assign_submissions(
	:'ven', :'roleeditor',
	jsonb_build_array(jsonb_build_object('externalid', 'M-ED2', 'person', :'ed1')),
	false
) as own \gset
select tests.clear_authentication();

select is(:'own'::jsonb->'rows'->0->>'verdict', 'recused', 'a caller who wrote the submission cannot assign on it');
select is(
	(select count(*)::int from public.assignments where submission = :'s_ed2'), 0,
	'nothing is written on the caller''s own submission'
);
select is(
	(:'own'::jsonb->>'skipped')::int, 1,
	'a priority-0 editor who is not an admin may call it'
);

select * from finish();
rollback;
