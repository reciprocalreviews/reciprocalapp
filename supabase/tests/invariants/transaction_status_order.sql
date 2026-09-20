-- The declared order of transaction_status is load-bearing.
--
-- All three paginated transaction lists in SupabaseCRUD sort by
-- `status asc, created_at desc, seq desc`, so that a proposed transaction is
-- always on the first page whatever its date — otherwise an approver's
-- outstanding work sinks behind however many pages of settled history have
-- accumulated since it was proposed, with nothing on screen to say it is there.
--
-- "Ascending puts proposed first" is a fact about this enum, not about the word
-- 'proposed': PostgreSQL orders enum values by the position their labels were
-- DECLARED in, not alphabetically. The type was created as
-- ('proposed', 'approved', 'canceled') and the third label was later renamed to
-- 'declined' — a rename keeps its position, which is why the order still reads
-- proposed → approved → declined and not alphabetically.
--
-- Nothing in the TypeScript can see any of that, and the failure it protects
-- against is silent: `alter type ... add value 'x' before 'proposed'` would
-- reorder every transaction list on the platform without a single test failing
-- anywhere else, and a type rebuilt from a fresh `create type` with the labels
-- written in a different order would do the same. Hence these assertions.
--
-- No fixtures and no authentication: this is a property of the type itself.
begin;

create extension if not exists pgtap
with
	schema extensions;

select
	plan (4);

select
	ok (
		'proposed'::public.transaction_status<'approved'::public.transaction_status,
		'proposed sorts before approved, so ascending status puts pending work first'
	);

select
	ok (
		'approved'::public.transaction_status<'declined'::public.transaction_status,
		'approved sorts before declined'
	);

-- Ordering the labels the way the queries do must reproduce the intended
-- sequence. This is the assertion that fails if a label is ever added ahead of
-- 'proposed', which the two pairwise checks above would not catch.
select
	is (
		(
			select
				array_agg(
					status
					order by
						status
				)::text[]
			from
				unnest(enum_range(null::public.transaction_status)) as status
		),
		array['proposed', 'approved', 'declined']::text[],
		'the full ascending order is proposed, approved, declined'
	);

-- A fourth status would not be wrong, but it would have to be placed
-- deliberately: anything sorting before 'proposed' displaces pending work from
-- the top of the list, and `alter type ... add value` appends to the END of the
-- order unless told otherwise, which may not be where it reads in the type.
select
	is (
		(
			select
				count(*)
			from
				unnest(enum_range(null::public.transaction_status))
		),
		3::bigint,
		'and there are exactly three statuses — a new one must be placed deliberately'
	);

select
	*
from
	finish ();

rollback;
