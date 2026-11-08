-- Tests for seating a venue's editor on a new submission, and for the claim branch that
-- lets a venue's editors seat themselves. Defined in migration
-- 20260828040000_editor_on_submission.sql.
--
-- Both halves are security-sensitive in the same way: a priority-0 assignment is what the
-- database checks when deciding who may approve any assignment on a submission, edit its
-- author list, and mark it done -- and mark_submission_done pays every approved
-- priority-0 assignment on the submission. So "who gets seated, and who may seat
-- themselves" is a permissions question and a money question at once, and these are the
-- cases that pin it down.
--
-- can_claim_editor_role is SECURITY INVOKER's opposite for a reason: it reads
-- public.assignments to decide whether a submission already has an editor, and that table
-- is RLS-gated, so the "nobody is editing this yet" test must not run as the claimer.
-- The "already has an editor" case below is what would fail if that ever changed.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(54);

-- ---- Fixtures (owner context) ------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('eos_minter@test.local') as minter \gset
select tests.create_scholar('eos_admin@test.local') as admin \gset
select tests.create_scholar('eos_editor@test.local') as editor \gset
select tests.create_scholar('eos_editor2@test.local') as editor2 \gset
select tests.create_scholar('eos_author@test.local') as author \gset
select tests.create_scholar('eos_outsider@test.local') as outsider \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset

-- Venue A: exactly one accepted editor, who is NOT the venue admin. That separation is
-- the point -- it is the case the claim branch exists for, and the case where seating
-- has to happen without an admin being involved at all.
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset
select tests.create_role(:'ven', 0) as editor_role \gset
select tests.create_volunteer(:'editor', :'editor_role') as v1 \gset
select tests.create_submission_type(:'ven', 1) as stype \gset

-- Venue B: two accepted editors, so the choice is ambiguous.
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven2 \gset
select tests.create_role(:'ven2', 0) as editor_role2 \gset
select tests.create_volunteer(:'editor', :'editor_role2') as v2 \gset
select tests.create_volunteer(:'editor2', :'editor_role2') as v3 \gset
select tests.create_submission_type(:'ven2', 1) as stype2 \gset

-- Venue C: no editors at all.
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven3 \gset
select tests.create_role(:'ven3', 0) as editor_role3 \gset
select tests.create_submission_type(:'ven3', 1) as stype3 \gset

-- Give the author enough tokens to cover a charge of 1 at each venue.
insert into public.tokens (currency, scholar) select :'cur', :'author' from generate_series(1, 6);
insert into public.tokens (currency, scholar) select :'cur', :'editor' from generate_series(1, 3);

--------------------------------------------------------------------------------
-- Seating on create_submission
--------------------------------------------------------------------------------
-- One eligible editor: they are seated, approved and not as a bid.
select tests.authenticate_as(:'author');
select lives_ok(
	$$ select public.create_submission( $$ || quote_literal(:'ven') || $$, 'EOS-1', null, null, $$
		|| quote_literal(:'stype') || $$, array[ $$ || quote_literal(:'author') || $$ ]::uuid[],
		array[1]::integer[], 'One editor', 'expertise', null, 'Payment for EOS-1' ) $$,
	'an author can create a submission at a venue with one editor'
);
select tests.clear_authentication();

select is(
	(select count(*)::int from public.assignments a
	 join public.submissions s on s.id = a.submission
	 where s.externalid = 'EOS-1' and a.scholar = :'editor' and a.role = :'editor_role'),
	1,
	'the venue''s sole editor is seated on the new submission'
);
select is(
	(select a.approved from public.assignments a
	 join public.submissions s on s.id = a.submission where s.externalid = 'EOS-1'),
	true,
	'the seated assignment is approved, so the editor can act on it'
);
select is(
	(select a.bid from public.assignments a
	 join public.submissions s on s.id = a.submission where s.externalid = 'EOS-1'),
	false,
	'the seated assignment is not a bid'
);

-- Two eligible editors: nobody is seated. Picking one would be arbitrary, and seating
-- both would bill the venue two editor fees for one paper.
select tests.authenticate_as(:'author');
select lives_ok(
	$$ select public.create_submission( $$ || quote_literal(:'ven2') || $$, 'EOS-2', null, null, $$
		|| quote_literal(:'stype2') || $$, array[ $$ || quote_literal(:'author') || $$ ]::uuid[],
		array[1]::integer[], 'Two editors', 'expertise', null, 'Payment for EOS-2' ) $$,
	'an author can create a submission at a venue with two editors'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.assignments a
	 join public.submissions s on s.id = a.submission where s.externalid = 'EOS-2'),
	0,
	'no editor is seated when the venue has two of them'
);

-- No editors: nobody is seated, and nothing raises.
select tests.authenticate_as(:'author');
select lives_ok(
	$$ select public.create_submission( $$ || quote_literal(:'ven3') || $$, 'EOS-3', null, null, $$
		|| quote_literal(:'stype3') || $$, array[ $$ || quote_literal(:'author') || $$ ]::uuid[],
		array[1]::integer[], 'No editors', 'expertise', null, 'Payment for EOS-3' ) $$,
	'a venue with no editors still accepts submissions'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.assignments a
	 join public.submissions s on s.id = a.submission where s.externalid = 'EOS-3'),
	0,
	'no editor is seated when the venue has none'
);

-- The sole editor submitting their own paper is not seated as its editor.
select tests.authenticate_as(:'editor');
select lives_ok(
	$$ select public.create_submission( $$ || quote_literal(:'ven') || $$, 'EOS-4', null, null, $$
		|| quote_literal(:'stype') || $$, array[ $$ || quote_literal(:'editor') || $$ ]::uuid[],
		array[1]::integer[], 'Editor''s own paper', 'expertise', null, 'Payment for EOS-4' ) $$,
	'the editor can submit their own paper'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.assignments a
	 join public.submissions s on s.id = a.submission where s.externalid = 'EOS-4'),
	0,
	'the sole editor is not seated on a submission they authored'
);

--------------------------------------------------------------------------------
-- Claiming an unclaimed submission
--------------------------------------------------------------------------------
-- EOS-2 is at the two-editor venue and has no editor, so either of them may take it.
select is(
	(select public.can_claim_editor_role(
		(select id from public.submissions where externalid = 'EOS-2'), :'editor_role2')),
	false,
	'can_claim_editor_role is false with no authenticated caller'
);

-- Before claiming anything, an editor must be able to SEE the submission. Every other
-- branch of the submissions SELECT policy needs a foothold on the row -- admin, author,
-- biddable-role volunteer, or an approved assignment -- and a venue editor who is not
-- also an admin has none of them on a submission nobody is editing yet. Without this the
-- claim below cannot even name its target.
select tests.authenticate_as(:'editor');
select is(
	(select count(*)::int from public.submissions where externalid = 'EOS-2'),
	1,
	'a venue editor who is not an admin can see an unassigned submission'
);

select tests.authenticate_as(:'editor');
select lives_ok(
	$$ insert into public.assignments (venue, submission, scholar, role, bid, approved)
	   values ( $$ || quote_literal(:'ven2') || $$,
	            (select id from public.submissions where externalid = 'EOS-2'),
	            $$ || quote_literal(:'editor') || $$, $$ || quote_literal(:'editor_role2') || $$,
	            false, true) $$,
	'an editor who is not a venue admin can claim an unclaimed submission'
);

-- And now the second editor cannot: the submission is no longer unclaimed. This is the
-- case that depends on can_claim_editor_role being SECURITY DEFINER -- :editor2 cannot
-- necessarily see :editor's assignment row, so an RLS-gated emptiness test would still
-- say "nobody is editing this".
select tests.authenticate_as(:'editor2');
select throws_ok(
	$$ insert into public.assignments (venue, submission, scholar, role, bid, approved)
	   values ( $$ || quote_literal(:'ven2') || $$,
	            (select id from public.submissions where externalid = 'EOS-2'),
	            $$ || quote_literal(:'editor2') || $$, $$ || quote_literal(:'editor_role2') || $$,
	            false, true) $$,
	'42501', null,
	'a second editor cannot claim a submission that already has one'
);

-- The branch seats the caller and nobody else.
select tests.authenticate_as(:'editor');
select throws_ok(
	$$ insert into public.assignments (venue, submission, scholar, role, bid, approved)
	   values ( $$ || quote_literal(:'ven3') || $$,
	            (select id from public.submissions where externalid = 'EOS-3'),
	            $$ || quote_literal(:'editor2') || $$, $$ || quote_literal(:'editor_role3') || $$,
	            false, true) $$,
	'42501', null,
	'an editor cannot use the claim branch to seat someone else'
);

-- ...and only someone who actually volunteers for the venue's editor role.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ insert into public.assignments (venue, submission, scholar, role, bid, approved)
	   values ( $$ || quote_literal(:'ven3') || $$,
	            (select id from public.submissions where externalid = 'EOS-3'),
	            $$ || quote_literal(:'outsider') || $$, $$ || quote_literal(:'editor_role3') || $$,
	            false, true) $$,
	'42501', null,
	'a scholar who does not volunteer for the editor role cannot claim'
);

-- ...and only for a priority-0 role. A non-editor role is not claimable this way, even
-- by an accepted volunteer on it.
select tests.clear_authentication();
select tests.create_role(:'ven3', 1) as reviewer_role \gset
select tests.create_volunteer(:'outsider', :'reviewer_role') as v4 \gset
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ insert into public.assignments (venue, submission, scholar, role, bid, approved)
	   values ( $$ || quote_literal(:'ven3') || $$,
	            (select id from public.submissions where externalid = 'EOS-3'),
	            $$ || quote_literal(:'outsider') || $$, $$ || quote_literal(:'reviewer_role') || $$,
	            false, true) $$,
	'42501', null,
	'the claim branch does not extend to non-editor roles'
);

--------------------------------------------------------------------------------
-- Reporting who has an editor, without reporting who they are
--------------------------------------------------------------------------------
-- The list needs to know whether a submission is claimed, and the venue's editors cannot
-- see assignment rows. These two answer that in one bit rather than by widening the
-- assignments policy, so what they must NOT do is become a second way to read it.
select tests.authenticate_as(:'editor');
select is(
	(select public.submission_has_editor((select id from public.submissions where externalid = 'EOS-1'))),
	true,
	'submission_has_editor sees the seated editor through the assignments policy'
);
select is(
	(select public.submission_has_editor((select id from public.submissions where externalid = 'EOS-3'))),
	false,
	'submission_has_editor is false for a submission nobody is editing'
);

-- The list form runs as the caller, so it reports on exactly the submissions they may
-- already see -- no more rows than the submissions policy would hand them anyway.
select is(
	(select count(*)::int from public.venue_submission_editors(:'ven')),
	(select count(*)::int from public.submissions where venue = :'ven'),
	'venue_submission_editors reports one row per submission the caller can see'
);

-- And an outsider, who can see none of the venue's submissions, learns nothing from it.
select tests.authenticate_as(:'outsider');
select is(
	(select count(*)::int from public.venue_submission_editors(:'ven')),
	0,
	'venue_submission_editors tells an outsider nothing'
);


--------------------------------------------------------------------------------
-- Seating on bulk_import_submissions
--------------------------------------------------------------------------------
-- A bulk import may name the person to seat on each row, in a role the importing admin
-- chose. Two things are being pinned here. First, that the named path reaches cases the
-- sole-editor rule cannot -- a venue with several editors, which is most of them.
-- Second, that naming somebody is never a way to acquire a role: the person must already
-- hold it, accepted and active, and a row that fails that check takes the whole import
-- down with it rather than leaving half a batch seated.
--
-- The priority-0 count assertions are the money ones. mark_submission_done pays every
-- approved priority-0 assignment on a submission, so "exactly one" is not tidiness.

select tests.clear_authentication();
-- An associate-editor role at each venue, so somebody can be seated below priority 0.
select tests.create_role(:'ven', 1) as ae_role \gset
select tests.create_volunteer(:'editor2', :'ae_role') as v5 \gset
select tests.create_role(:'ven2', 1) as ae_role2 \gset
select tests.create_volunteer(:'author', :'ae_role2') as v6 \gset

select tests.authenticate_as(:'admin');

-- Venue B has two editors, so the sole-editor rule seats nobody. Naming one is the only
-- way these submissions get an editor at import, and it is the case the column is for.
select lives_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven2') || $$,
		'[{"externalid":"BI-B-1","title":"Named at an ambiguous venue","submission_type":"$$
		|| :'stype2' || $$","people":[{"person":"$$ || :'editor2' || $$","person_role":"$$
		|| :'editor_role2' || $$"}]}]'::jsonb, '' ) $$,
	'a bulk import can name an editor at a venue with several'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.assignments a
		join public.roles r on r.id = a.role
		join public.submissions s on s.id = a.submission
		where s.externalid = 'BI-B-1' and r.priority = 0),
	1,
	'the named editor is seated where the sole-editor rule would seat nobody'
);
select is(
	(select a.scholar from public.assignments a
		join public.submissions s on s.id = a.submission
		where s.externalid = 'BI-B-1'),
	:'editor2'::uuid,
	'and it is the person the row named'
);

-- Venue A has one editor. Naming an associate editor should seat both: the AE in the
-- role named, and the venue's own editor by the existing fallback.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$,
		'[{"externalid":"BI-A-1","title":"Named associate editor","submission_type":"$$
		|| :'stype' || $$","people":[{"person":"$$ || :'editor2' || $$","person_role":"$$
		|| :'ae_role' || $$"}]}]'::jsonb, '' ) $$,
	'a bulk import can name somebody for a role below the top one'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.assignments a
		join public.roles r on r.id = a.role
		join public.submissions s on s.id = a.submission
		where s.externalid = 'BI-A-1' and r.priority = 0),
	1,
	'the venue''s sole editor is still seated alongside a named associate editor'
);
select is(
	(select count(*)::int from public.assignments a
		join public.roles r on r.id = a.role
		join public.submissions s on s.id = a.submission
		where s.externalid = 'BI-A-1' and r.priority = 1),
	1,
	'and the named associate editor is seated in the role the import chose'
);

-- A row naming nobody still gets the venue's editor, exactly as before this change.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$,
		'[{"externalid":"BI-A-2","title":"Nobody named","submission_type":"$$
		|| :'stype' || $$"}]'::jsonb, '' ) $$,
	'a bulk import row may still name nobody'
);
select tests.clear_authentication();
select is(
	(select a.scholar from public.assignments a
		join public.submissions s on s.id = a.submission
		where s.externalid = 'BI-A-2'),
	:'editor'::uuid,
	'a row naming nobody falls back to the venue''s sole editor'
);

-- Naming the venue's own editor for the editor role must not seat them twice: the
-- fallback has to stand down. Two priority-0 assignments would be paid twice.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$,
		'[{"externalid":"BI-A-3","title":"Named the sole editor","submission_type":"$$
		|| :'stype' || $$","people":[{"person":"$$ || :'editor' || $$","person_role":"$$
		|| :'editor_role' || $$"}]}]'::jsonb, '' ) $$,
	'a bulk import may name the venue''s own sole editor'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.assignments a
		join public.submissions s on s.id = a.submission
		where s.externalid = 'BI-A-3'),
	1,
	'naming the sole editor seats them once, not twice'
);

-- Seating is not a way to acquire a role. The outsider holds nothing at this venue.
select tests.authenticate_as(:'admin');
select throws_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$,
		'[{"externalid":"BI-A-4","title":"Ineligible","submission_type":"$$
		|| :'stype' || $$","people":[{"person":"$$ || :'outsider' || $$","person_role":"$$
		|| :'editor_role' || $$"}]}]'::jsonb, '' ) $$,
	'A named person must already be an accepted, active volunteer in that role',
	'a bulk import cannot seat somebody who does not hold the role'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.submissions where externalid = 'BI-A-4'),
	0,
	'the refused import left no submission behind'
);

-- A role belonging to another venue is refused, so an admin cannot reach across venues.
select tests.authenticate_as(:'admin');
select throws_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$,
		'[{"externalid":"BI-A-5","title":"Foreign role","submission_type":"$$
		|| :'stype' || $$","people":[{"person":"$$ || :'editor2' || $$","person_role":"$$
		|| :'editor_role2' || $$"}]}]'::jsonb, '' ) $$,
	'That role does not belong to this venue',
	'a bulk import cannot seat somebody in another venue''s role'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.submissions where externalid = 'BI-A-5'),
	0,
	'the cross-venue import left no submission behind'
);


--------------------------------------------------------------------------------
-- Several roles seated from several columns
--------------------------------------------------------------------------------
-- An export commonly names an editor in chief and a handling editor in separate
-- columns: two people, two roles, one manuscript. The rules that matter here are
-- that both get seated, that at most one priority-0 assignment lands on a row --
-- mark_submission_done pays every one of them -- and that neither guarantee leaks
-- across rows.

select tests.clear_authentication();
select tests.create_role(:'ven', 2) as rev_role \gset
select tests.create_volunteer(:'author', :'rev_role') as v7 \gset

-- Venue D: two priority-0 roles. Nothing constrains roles.priority to be unique
-- within a venue, and one menu per role means an admin can match a column to each.
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven4 \gset
select tests.create_role(:'ven4', 0) as eic_role4 \gset
select tests.create_role(:'ven4', 0) as chair_role4 \gset
select tests.create_volunteer(:'editor', :'eic_role4') as v8 \gset
select tests.create_volunteer(:'editor2', :'chair_role4') as v9 \gset
select tests.create_submission_type(:'ven4', 1) as stype4 \gset

select tests.authenticate_as(:'admin');
select lives_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$,
		'[{"externalid":"BI-M-1","title":"Two roles from two columns","submission_type":"$$
		|| :'stype' || $$","people":[{"person":"$$ || :'editor2' || $$","person_role":"$$
		|| :'ae_role' || $$"},{"person":"$$ || :'author' || $$","person_role":"$$
		|| :'rev_role' || $$"}]}]'::jsonb, '' ) $$,
	'a bulk import can seat several roles on one submission'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.assignments a
		join public.submissions s on s.id = a.submission
		where s.externalid = 'BI-M-1'),
	3,
	'both named people are seated, alongside the venue''s own editor'
);
select is(
	(select count(*)::int from public.assignments a
		join public.roles r on r.id = a.role
		join public.submissions s on s.id = a.submission
		where s.externalid = 'BI-M-1' and r.priority = 0),
	1,
	'and still exactly one editor on the submission'
);

-- Naming the top role AND another role: the fallback stands down for the first,
-- the second is seated anyway. This is the money case.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$,
		'[{"externalid":"BI-M-2","title":"Top role and another","submission_type":"$$
		|| :'stype' || $$","people":[{"person":"$$ || :'editor' || $$","person_role":"$$
		|| :'editor_role' || $$"},{"person":"$$ || :'editor2' || $$","person_role":"$$
		|| :'ae_role' || $$"}]}]'::jsonb, '' ) $$,
	'a row may name the top role and another role at once'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.assignments a
		join public.roles r on r.id = a.role
		join public.submissions s on s.id = a.submission
		where s.externalid = 'BI-M-2' and r.priority = 0),
	1,
	'naming the top role stands the fallback down rather than adding to it'
);
select is(
	(select count(*)::int from public.assignments a
		join public.submissions s on s.id = a.submission
		where s.externalid = 'BI-M-2'),
	2,
	'and the other named role is seated alongside it'
);

-- Two entries for one role would be two claims on the reserve for one job.
select tests.authenticate_as(:'admin');
select throws_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$,
		'[{"externalid":"BI-M-3","title":"Same role twice","submission_type":"$$
		|| :'stype' || $$","people":[{"person":"$$ || :'editor2' || $$","person_role":"$$
		|| :'ae_role' || $$"},{"person":"$$ || :'author' || $$","person_role":"$$
		|| :'ae_role' || $$"}]}]'::jsonb, '' ) $$,
	'A submission cannot seat two people in the same role',
	'two people cannot be seated in the same role on one submission'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.submissions where externalid = 'BI-M-3'),
	0,
	'the refused row left no submission behind'
);

-- Two DIFFERENT priority-0 roles is the case the form cannot rule out, since each
-- role gets its own menu. Checking the priority rather than the role is what
-- catches it.
select tests.authenticate_as(:'admin');
select throws_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven4') || $$,
		'[{"externalid":"BI-M-4","title":"Two top roles","submission_type":"$$
		|| :'stype4' || $$","people":[{"person":"$$ || :'editor' || $$","person_role":"$$
		|| :'eic_role4' || $$"},{"person":"$$ || :'editor2' || $$","person_role":"$$
		|| :'chair_role4' || $$"}]}]'::jsonb, '' ) $$,
	'A submission can have only one editor',
	'two distinct priority-0 roles cannot both be seated on one submission'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.submissions where externalid = 'BI-M-4'),
	0,
	'the two-editor row left no submission behind'
);

-- A bad entry after a good one must undo the good one too. Asserting only that the
-- submission is gone would pass even if the assignment survived.
select tests.authenticate_as(:'admin');
select throws_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$,
		'[{"externalid":"BI-M-5","title":"Good entry then bad","submission_type":"$$
		|| :'stype' || $$","people":[{"person":"$$ || :'editor2' || $$","person_role":"$$
		|| :'ae_role' || $$"},{"person":"$$ || :'outsider' || $$","person_role":"$$
		|| :'rev_role' || $$"}]}]'::jsonb, '' ) $$,
	'A named person must already be an accepted, active volunteer in that role',
	'one ineligible entry refuses the whole row'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.assignments a
		where a.scholar = :'editor2'::uuid and a.role = :'ae_role'::uuid
			and a.submission in (select id from public.submissions where externalid = 'BI-M-5')),
	0,
	'and the assignment the earlier entry had already written is rolled back too'
);

-- The per-row reset. Its failure mode is silent: the right row count, the right
-- mint, no error, and no editor on anything after the first row.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$,
		'[{"externalid":"BI-M-6","title":"Row one","submission_type":"$$
		|| :'stype' || $$","people":[{"person":"$$ || :'editor' || $$","person_role":"$$
		|| :'editor_role' || $$"}]},
		  {"externalid":"BI-M-7","title":"Row two","submission_type":"$$
		|| :'stype' || $$","people":[{"person":"$$ || :'editor2' || $$","person_role":"$$
		|| :'ae_role' || $$"}]}]'::jsonb, '' ) $$,
	'a batch may name different roles on different rows'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.assignments a
		join public.roles r on r.id = a.role
		join public.submissions s on s.id = a.submission
		where s.externalid in ('BI-M-6', 'BI-M-7') and r.priority = 0),
	2,
	'each row gets its own editor: the first row''s naming does not suppress the second''s fallback'
);
select is(
	(select count(*)::int from public.assignments a
		join public.submissions s on s.id = a.submission
		where s.externalid = 'BI-M-7'),
	2,
	'and the second row keeps both its named associate editor and its fallback editor'
);

-- A blank cell in one role's column says nothing about the other roles.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$,
		'[{"externalid":"BI-M-8","title":"Blank entry","submission_type":"$$
		|| :'stype' || $$","people":[{"person":"","person_role":"$$
		|| :'ae_role' || $$"}]}]'::jsonb, '' ) $$,
	'an entry naming nobody is skipped rather than refused'
);
select tests.clear_authentication();
select is(
	(select a.scholar from public.assignments a
		join public.submissions s on s.id = a.submission
		where s.externalid = 'BI-M-8'),
	:'editor'::uuid,
	'and the row still falls back to the venue''s sole editor'
);

-- A person with no role. This branch existed with no test.
select tests.authenticate_as(:'admin');
select throws_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$,
		'[{"externalid":"BI-M-9","title":"No role","submission_type":"$$
		|| :'stype' || $$","people":[{"person":"$$ || :'editor2' || $$"}]}]'::jsonb, '' ) $$,
	'A named person needs a role to be seated in',
	'a named person with no role is refused'
);

-- Malformed input, which the array shape makes visible rather than silently
-- de-duplicating the way a role-keyed object would.
select tests.authenticate_as(:'admin');
select throws_ok(
	$$ select public.bulk_import_submissions( $$ || quote_literal(:'ven') || $$,
		'[{"externalid":"BI-M-10","title":"Not a list","submission_type":"$$
		|| :'stype' || $$","people":{}}]'::jsonb, '' ) $$,
	'A row''s people must be a list of person and role pairs',
	'people must be a list'
);
select tests.clear_authentication();

select * from finish();
rollback;
