-- Who may EXECUTE each SECURITY DEFINER function.
--
-- WHY THIS FILE EXISTS
--
-- `revoke execute on function ... from public` does not do what it looks like it
-- does. Supabase's default privileges grant anon, authenticated and service_role
-- EXECUTE on every function created in `public` before that revoke runs, and
-- revoking from PUBLIC leaves the explicit per-role grants in place. So a
-- function can read as owner-only in supabase/schemas/ and still be callable by
-- anyone on the internet at POST /rest/v1/rpc/<name>.
--
-- That is not hypothetical. Before 20260831000000, public._move_tokens -- which
-- is SECURITY DEFINER and performs no authorization of its own, because it trusts
-- its six callers to have done it -- was anon-executable. A single anonymous POST
-- with the publishable key emptied a venue's reserve and minted a thousand tokens
-- out of nothing. public._welcome_volunteer had the same shape and predates that
-- work entirely.
--
-- `supabase db diff` does NOT compare function ACLs, so the CI drift check that
-- guards the rest of this schema is blind here. **This file is the only thing
-- standing between that trap and its next recurrence.** A new SECURITY DEFINER
-- function must be added to the sweep migration's lists and, if it is meant to be
-- reachable without a session, to the allowlist below -- otherwise this fails.
begin;

create extension if not exists pgtap
with
	schema extensions;

select
	plan (5);

--------------------------------------------------------------------------------
-- The allowlist: functions that may be called without a session.
--------------------------------------------------------------------------------
-- Twelve of these are RLS policy predicates, and their openness is load-bearing
-- rather than an oversight. A policy expression is evaluated as the QUERYING
-- role, so that role needs EXECUTE on every function the policy calls; the
-- `submissions` SELECT policy is granted to {anon, authenticated} and calls
-- isAdmin, isPriorityZero and isRoleApproverVolunteer. They are safe to leave
-- open because each is a read-only predicate about the CALLER's own
-- relationships -- auth.uid(), which is null for anon -- over inputs
-- (venues.admins, currencies.minters) that are publicly readable anyway.
--
-- The other two are deliberate product decisions: verify_email is followed from a
-- link in an email before the recipient has signed in, and currency_holder_counts
-- returns only aggregates -- total supply and holder COUNTS, never a balance --
-- which DESIGN.md holds should be public ("the oversight on supply is the public
-- ledger").
create temporary table anon_allowed (name text primary key);

insert into
	anon_allowed (name)
values
	('isadmin'),
	('issteward'),
	('isminter'),
	('ispriorityzero'),
	('isassigned'),
	('isauthor'),
	('isconflicted'),
	('isinapproverchain'),
	('isroleapprovervolunteer'),
	('can_approve_assignment'),
	('can_claim_editor_role'),
	('submission_has_editor'),
	('verify_email'),
	('currency_holder_counts');

--------------------------------------------------------------------------------
-- 1. Nothing outside the allowlist is reachable without a session.
--------------------------------------------------------------------------------
select
	is_empty (
		$$
		select p.proname
		from pg_proc p
		join pg_namespace n on n.oid = p.pronamespace
		where n.nspname = 'public'
			and p.prokind = 'f'
			and p.prosecdef
			and has_function_privilege('anon', p.oid, 'execute')
			and p.proname not in (select name from anon_allowed)
		$$,
		'no SECURITY DEFINER function is anon-executable unless allowlisted'
	);

--------------------------------------------------------------------------------
-- 2. The allowlist is not stale: every entry still names a real function.
-- Without this, a renamed function would leave a permanent hole in check 1.
--------------------------------------------------------------------------------
select
	is_empty (
		$$
		select a.name from anon_allowed a
		where not exists (
			select 1 from pg_proc p
			join pg_namespace n on n.oid = p.pronamespace
			where n.nspname = 'public' and p.prokind = 'f' and p.prosecdef
				and p.proname = a.name
		)
		$$,
		'every allowlisted name still exists as a SECURITY DEFINER function'
	);

--------------------------------------------------------------------------------
-- 3. Internal helpers are owner-only. These are the dangerous ones: they are
-- steps of an RPC that has already authorized the caller, so they perform NO
-- authorization themselves. Neither anon nor authenticated may reach them.
--------------------------------------------------------------------------------
select
	is_empty (
		$$
		select p.proname || ' (' ||
			case when has_function_privilege('anon', p.oid, 'execute') then 'anon ' else '' end ||
			case when has_function_privilege('authenticated', p.oid, 'execute') then 'authenticated' else '' end || ')'
		from pg_proc p
		join pg_namespace n on n.oid = p.pronamespace
		where n.nspname = 'public'
			and p.prokind = 'f'
			and p.prosecdef
			and p.proname like '\_%'
			and (
				has_function_privilege('anon', p.oid, 'execute')
				or has_function_privilege('authenticated', p.oid, 'execute')
			)
		$$,
		'no underscore-prefixed internal helper is reachable by anon or authenticated'
	);

--------------------------------------------------------------------------------
-- 4. _move_tokens specifically. Named rather than left to the pattern above,
-- because it is the one that was actually exploited and the one whose blast
-- radius is the entire token economy: it moves tokens between arbitrary holders
-- and, with _mint_shortfall, creates them from nothing.
--------------------------------------------------------------------------------
select
	ok (
		not has_function_privilege ('anon', 'public._move_tokens(uuid,uuid,uuid,uuid,uuid,integer,text,boolean)', 'execute')
		and not has_function_privilege ('authenticated', 'public._move_tokens(uuid,uuid,uuid,uuid,uuid,integer,text,boolean)', 'execute'),
		'_move_tokens is reachable only by its owner and the service role'
	);

--------------------------------------------------------------------------------
-- 5. Operational functions stay with the service role that runs the crons.
-- tokens_as_of is here rather than under "internal" because its name gives no
-- warning: it reconstructs every token's owner at any past instant, which is
-- exactly what token_events RLS withholds, since it "would leak reviewing
-- activity that venue anonymity settings are meant to protect".
--------------------------------------------------------------------------------
select
	is_empty (
		$$
		select p.proname
		from pg_proc p
		join pg_namespace n on n.oid = p.pronamespace
		where n.nspname = 'public'
			and p.prokind = 'f'
			and p.proname in ('tokens_as_of', 'reconcile_ledger', 'replay_audit_log', 'site_origin')
			and (
				has_function_privilege('anon', p.oid, 'execute')
				or has_function_privilege('authenticated', p.oid, 'execute')
			)
		$$,
		'operational functions are reachable only by the service role'
	);

select
	*
from
	finish ();

rollback;
