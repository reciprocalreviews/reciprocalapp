-- Importing a backlog before everyone named in it has an account.
--
-- Under test:
--   * bulk_import_submissions keeps an unmatched name as an unmatched assignment, which
--     still leaves the submission waiting for an editor.
--   * unmatched_assignments RLS: whoever could approve the assignment sees it -- an
--     admin all of them, an associate editor only the reviewers on their own submissions.
--   * public.request_compensation: a volunteer files a claim on a submission nobody
--     assigned them to; who may, on what, and who hears about it.
--   * public.match_assignments: matching every row held under a name that the caller
--     may approve, and approving an existing claim rather than duplicating it.
--   * complete_assignment approves and pays a claim in one step, declined or not;
--     decline_bid declines one.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(35);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('ua_minter@test.local') as minter \gset
select tests.create_scholar('ua_admin@test.local') as admin \gset
select tests.create_scholar('ua_ae@test.local') as ae \gset
select tests.create_scholar('ua_reviewer@test.local') as reviewer \gset
select tests.create_scholar('ua_joiner@test.local') as joiner \gset
select tests.create_scholar('ua_newreviewer@test.local') as newreviewer \gset
select tests.create_scholar('ua_outsider@test.local') as outsider \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

-- An editor role nobody holds yet; an associate editor role that approves reviewers.
-- Reviewing is not biddable, so the reviewer cannot see submissions they are not on.
select tests.create_role(:'ven', 0, null, false, false) as roleeditor \gset
select tests.create_role(:'ven', 1, null, false, false) as roleae \gset
select tests.create_role(:'ven', 2, :'roleae', false, false) as rolereviewer \gset
select tests.create_volunteer(:'reviewer', :'rolereviewer', 'accepted') as v_reviewer \gset
select tests.create_volunteer(:'ae', :'roleae', 'accepted') as v_ae \gset

select tests.create_submission_type(:'ven') as stype \gset
insert into public.compensation (submission_type, role, amount) values (:'stype', :'rolereviewer', 1);
insert into public.tokens (currency, venue) select :'cur', :'ven' from generate_series(1, 5);

-- A submission the reviewer is an author of.
select tests.create_submission(:'ven', :'stype', array[:'reviewer']::uuid[]) as own \gset

-- ---- Import keeps the names it cannot match --------------------------------------
select tests.authenticate_as(:'admin');
select public.bulk_import_submissions(
	:'ven',
	jsonb_build_array(
		jsonb_build_object('externalid', 'M-1', 'submission_type', :'stype', 'title', 'One',
			'people', jsonb_build_array(
				jsonb_build_object('name', ' Jane Doe ', 'person_role', :'roleeditor'),
				jsonb_build_object('name', 'Rev Unknown', 'person_role', :'rolereviewer'))),
		jsonb_build_object('externalid', 'M-2', 'submission_type', :'stype', 'title', 'Two',
			'people', jsonb_build_array(
				jsonb_build_object('name', 'Jane Doe', 'person_role', :'roleeditor'),
				jsonb_build_object('name', 'Rev Unknown', 'person_role', :'rolereviewer')))
	),
	'backlog'
) as imported \gset

select is((:'imported'::jsonb ->> 'unmatched')::int, 4, 'each unmatched name becomes an unmatched assignment');
select is((:'imported'::jsonb ->> 'waiting')::int, 2, 'an unmatched editor still leaves the submission waiting for an editor');
select is((:'imported'::jsonb ->> 'seated')::int, 0, 'an unmatched name assigns nobody');

select tests.clear_authentication();
select id as m1 from public.submissions where venue = :'ven' and externalid = 'M-1' \gset
select id as m2 from public.submissions where venue = :'ven' and externalid = 'M-2' \gset

select results_eq(
	$$ select name from public.unmatched_assignments where venue = $$ || quote_literal(:'ven') || $$ and role = $$ || quote_literal(:'roleeditor') || $$ order by name $$,
	$$ values ('Jane Doe'), ('Jane Doe') $$,
	'unmatched assignments keep the trimmed name from the file'
);

select tests.authenticate_as(:'outsider');
select throws_ok(
	format(
		$$ select public.bulk_import_submissions(%L, jsonb_build_array(jsonb_build_object('externalid', 'M-3', 'submission_type', %L, 'people', jsonb_build_array(jsonb_build_object('person', %L, 'name', 'X', 'person_role', %L)))), '') $$,
		:'ven', :'stype', :'reviewer', :'rolereviewer'
	),
	'P0001',
	'Only venue admins can bulk import submissions',
	'only admins import'
);

-- ---- Who sees them: whoever could approve them ---------------------------------
-- The associate editor is assigned to M-1 only.
select tests.clear_authentication();
select tests.create_assignment(:'ven', :'m1', :'ae', :'roleae') as asg_ae \gset

select tests.authenticate_as(:'admin');
select is((select count(*)::int from public.unmatched_assignments where venue = :'ven'), 4, 'an admin sees every unmatched assignment at the venue');

select tests.authenticate_as(:'ae');
select results_eq(
	$$ select submission, role from public.unmatched_assignments $$,
	format($$ values (%L::uuid, %L::uuid) $$, :'m1', :'rolereviewer'),
	'an associate editor sees only the reviewers missing from their own submissions'
);

select tests.authenticate_as(:'outsider');
select is_empty($$ select 1 from public.unmatched_assignments $$, 'an outsider sees none');

select tests.authenticate_as(:'reviewer');
select is_empty($$ select 1 from public.unmatched_assignments $$, 'a reviewer sees none');

-- ---- Filing a claim -------------------------------------------------------------
select tests.authenticate_as_anon();
select throws_ok(
	format($$ select public.request_compensation(%L, 'M-1', %L) $$, :'ven', :'rolereviewer'),
	'42501',
	null,
	'an anonymous visitor cannot call request_compensation'
);

select tests.authenticate_as(:'reviewer');
select throws_ok(
	format($$ select public.request_compensation(%L, 'NOPE', %L) $$, :'ven', :'rolereviewer'),
	'RR020',
	null,
	'an unknown manuscript ID is refused'
);

select throws_ok(
	format($$ select public.request_compensation(%L, 'M-2', %L) $$, :'ven', :'roleeditor'),
	'RR023',
	null,
	'a claim cannot be filed in an editor role'
);

select throws_ok(
	format($$ select public.request_compensation(%L, %L, %L) $$, :'ven', :'own', :'rolereviewer'),
	'RR024',
	null,
	'an author cannot claim compensation on their own submission'
);

select tests.authenticate_as(:'outsider');
select throws_ok(
	format($$ select public.request_compensation(%L, 'M-2', %L) $$, :'ven', :'rolereviewer'),
	'RR024',
	null,
	'a scholar who does not volunteer in the role cannot file a claim'
);

select tests.authenticate_as(:'reviewer');
select public.request_compensation(:'ven', ' M-2 ', :'rolereviewer') as claim2 \gset

select is(
	:'claim2'::jsonb -> 'recipients',
	jsonb_build_array(:'admin'),
	'with nobody approving on the submission, the claim is announced to the venue''s admins'
);

select results_eq(
	$$ select bid, approved, completed, compensation_requested_at is not null
	   from public.assignments where submission = $$ || quote_literal(:'m2'),
	$$ values (false, false, false, true) $$,
	'a claim is an unapproved, non-bid assignment stamped with the request, visible to its claimant'
);

select throws_ok(
	$$ update public.assignments set approved = true where submission = $$ || quote_literal(:'m2'),
	'RR018',
	null,
	'a claimant cannot approve their own claim'
);

-- On M-1 the associate editor approves reviewers, so they hear about it too.
select results_eq(
	format($$ select r from jsonb_array_elements_text(public.request_compensation(%L, 'M-1', %L) -> 'recipients') r order by r $$, :'ven', :'rolereviewer'),
	format($$ select r from unnest(array[%L, %L]) r order by r $$, :'admin', :'ae'),
	'the holder of the approving role on the submission hears about a claim alongside the admins'
);

-- ---- Matching ------------------------------------------------------------------
select tests.authenticate_as(:'outsider');
select throws_ok(
	format($$ select public.match_assignments(%L, 'Jane Doe', %L, %L) $$, :'ven', :'roleeditor', :'reviewer'),
	'RR019',
	null,
	'the matched scholar must hold the role'
);

select tests.clear_authentication();
select tests.create_volunteer(:'joiner', :'roleeditor', 'accepted') as v_joiner \gset
select tests.create_volunteer(:'newreviewer', :'rolereviewer', 'accepted') as v_newreviewer \gset

select tests.authenticate_as(:'outsider');
select throws_ok(
	format($$ select public.match_assignments(%L, 'Jane Doe', %L, %L) $$, :'ven', :'roleeditor', :'joiner'),
	'P0001',
	'You cannot match any assignments under that name and role',
	'someone who approves none of them cannot match them'
);

-- The associate editor may match only the one on their own submission.
select tests.authenticate_as(:'ae');
select is(
	jsonb_array_length(public.match_assignments(:'ven', 'Rev Unknown', :'rolereviewer', :'newreviewer') -> 'matched'),
	1,
	'an associate editor matches only the reviewer rows they could approve'
);

select tests.authenticate_as(:'admin');
select is(
	(select count(*)::int from public.unmatched_assignments where name = 'Rev Unknown'),
	1,
	'the row on the submission they do not hold is left for someone who can'
);

select public.match_assignments(:'ven', 'Jane Doe', :'roleeditor', :'joiner') as matched \gset
select is(jsonb_array_length(:'matched'::jsonb -> 'matched'), 2, 'an admin matches every row held under the name');
select is_empty(
	$$ select 1 from public.unmatched_assignments where name = 'Jane Doe' $$,
	'matched rows are removed'
);

select tests.clear_authentication();
select is(
	(select count(*)::int from public.assignments where scholar = :'joiner' and role = :'roleeditor' and approved),
	2,
	'the scholar is assigned, approved, on each submission'
);

-- A row skipped because the role is already held is kept.
insert into public.unmatched_assignments (venue, submission, role, name) values (:'ven', :'own', :'roleeditor', 'Someone Else');
insert into public.assignments (venue, submission, scholar, role, approved) values (:'ven', :'own', :'joiner', :'roleeditor', true);
select tests.create_scholar('ua_other@test.local') as other \gset
select tests.create_volunteer(:'other', :'roleeditor', 'accepted') as v_other \gset
select tests.authenticate_as(:'admin');
select is(
	(public.match_assignments(:'ven', 'Someone Else', :'roleeditor', :'other') ->> 'skipped')::int,
	1,
	'a row whose role someone else already holds is skipped'
);

-- Matching the claimant onto the row where they already filed a claim (the "Rev Unknown"
-- the associate editor could not reach) approves the claim.
select tests.authenticate_as(:'admin');
select lives_ok(
	format($$ select public.match_assignments(%L, 'Rev Unknown', %L, %L) $$, :'ven', :'rolereviewer', :'reviewer'),
	'matching a claimant onto their own claim lives'
);
select tests.clear_authentication();
select results_eq(
	$$ select count(*)::int, bool_and(approved) from public.assignments where submission = $$ || quote_literal(:'m2') || $$ and scholar = $$ || quote_literal(:'reviewer'),
	$$ values (1, true) $$,
	'the existing claim is approved rather than duplicated'
);

-- ---- Answering claims --------------------------------------------------------------
-- The editor, now assigned on M-1, pays the reviewer's claim there in one step.
select tests.authenticate_as(:'joiner');
select is(
	public.complete_assignment(
		(select id from public.assignments where submission = :'m1' and scholar = :'reviewer'),
		'Paid {role}', 'Mint {amount}'
	) ->> 'status',
	'transferred',
	'an approver approves and pays a claim in one step'
);

select tests.clear_authentication();
select results_eq(
	$$ select approved, completed from public.assignments where submission = $$ || quote_literal(:'m1') || $$ and scholar = $$ || quote_literal(:'reviewer'),
	$$ values (true, true) $$,
	'a paid claim is approved and completed'
);

select tests.authenticate_as(:'reviewer');
select throws_ok(
	format($$ select public.request_compensation(%L, 'M-1', %L) $$, :'ven', :'rolereviewer'),
	'RR021',
	null,
	'work already paid for cannot be claimed again'
);

-- A fresh claim by the new reviewer on M-2, declined and then paid after all.
select tests.authenticate_as(:'newreviewer');
select public.request_compensation(:'ven', 'M-2', :'rolereviewer') as claim3 \gset
select tests.authenticate_as(:'joiner');
select lives_ok(
	format(
		$$ select public.decline_bid((select id from public.assignments where submission = %L and scholar = %L), 'No review on record.') $$,
		:'m2', :'newreviewer'
	),
	'an approver can decline a claim, with a reason'
);

select tests.authenticate_as(:'newreviewer');
select throws_ok(
	format($$ select public.request_compensation(%L, 'M-2', %L) $$, :'ven', :'rolereviewer'),
	'RR022',
	null,
	'a declined claim cannot be filed again'
);

select tests.authenticate_as(:'joiner');
select is(
	public.complete_assignment(
		(select id from public.assignments where submission = :'m2' and scholar = :'newreviewer'),
		'Paid {role}', 'Mint {amount}'
	) ->> 'status',
	'transferred',
	'an approver can still pay a declined claim, changing their mind'
);

select tests.clear_authentication();
select results_eq(
	$$ select approved, completed, declined_at is null from public.assignments where submission = $$ || quote_literal(:'m2') || $$ and scholar = $$ || quote_literal(:'newreviewer'),
	$$ values (true, true, true) $$,
	'paying a declined claim clears the decline'
);

select * from finish();
rollback;
