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
select plan(21);

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

select * from finish();
rollback;
