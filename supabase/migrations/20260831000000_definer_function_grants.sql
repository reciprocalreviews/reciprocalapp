-- Close the SECURITY DEFINER functions that Supabase left open to `anon`.
--
-- THE TRAP
--
-- `revoke execute on function ... from public` does NOT remove Supabase's
-- default grants. ALTER DEFAULT PRIVILEGES hands `anon`, `authenticated` and
-- `service_role` EXECUTE on every function created in `public` before the revoke
-- runs, and revoking from PUBLIC leaves those explicit per-role grants standing.
-- So a function whose file says
--
--     revoke execute on function public._move_tokens (...) from public;
--
-- with no grant after it reads as owner-only and is in fact callable by anyone
-- on the internet at POST /rest/v1/rpc/_move_tokens with the publishable key.
--
-- This is the same Supabase default-privileges trap already documented twice in
-- this schema for TABLES -- token_events.sql ("Explicitly revoked, not merely
-- un-granted") and tokens.sql ("`grant all` above confers TABLE-level
-- INSERT/UPDATE/DELETE that a policy alone cannot subtract") -- appearing a third
-- time for FUNCTIONS, where nobody had looked. public._notify_new_volunteer is
-- the one function that got it right; it revokes `from public, anon,
-- authenticated`, and its neighbours copied the comment without the third line.
--
-- WHAT WAS REACHABLE
--
-- Two functions perform no authorization of their own, by design, because they
-- are steps of an RPC that has already authorized the caller:
--
--   public._move_tokens       moves tokens between arbitrary holders, and with
--                             _mint_shortfall => true creates them from nothing
--   public._welcome_volunteer grants a venue's welcome amount to any scholar
--
-- Demonstrated on a local stack before this migration: an anonymous POST to
-- _move_tokens with only the publishable key emptied a venue's reserve of 50
-- tokens and minted 950 more into a scholar's balance. No session, no scholar
-- row, no venue membership.
--
-- Two more leaked reads that RLS elsewhere deliberately closes:
--
--   public.tokens_as_of       every token's ownership at any past instant --
--                             precisely what token_events RLS exists to withhold,
--                             since it "would leak reviewing activity that venue
--                             anonymity settings are meant to protect"
--   public.reconcile_ledger   the integrity of the whole economy, and it WRITES
--                             (a reconciliations row, and steward mail on failure)
--
-- The rest were untidy rather than exploitable: they check auth.uid() and fail
-- closed for an anonymous caller. They are corrected anyway, because "it happens
-- to be safe" is not a property anyone should have to re-derive.
--
-- WHAT IS DELIBERATELY LEFT OPEN
--
-- The twelve policy-predicate helpers (isAdmin, isSteward, isMinter,
-- isPriorityZero, isAssigned, isAuthor, isConflicted, isInApproverChain,
-- isRoleApproverVolunteer, can_approve_assignment, can_claim_editor_role,
-- submission_has_editor) keep EXECUTE for both anon and authenticated, and this
-- is load-bearing rather than an oversight: an RLS policy expression is evaluated
-- as the QUERYING role, so that role needs EXECUTE on every function the policy
-- calls. The `submissions` SELECT policy is granted to {anon, authenticated} and
-- calls isAdmin, isPriorityZero and isRoleApproverVolunteer, so revoking those
-- from anon would break anonymous submission viewing outright. They are safe to
-- leave open: each is a read-only predicate about the CALLER's own relationships
-- (auth.uid(), which is null for anon), over inputs -- venues.admins,
-- currencies.minters -- that are publicly readable already.
--
-- Written as a loop over named lists rather than fifty hand-written statements,
-- for the reason audit_log.sql gives for the same shape: the list is the
-- documentation, and adding a function later is a one-line change that cannot be
-- half-applied. Signatures come from pg_proc, so an overload cannot be missed and
-- a typo'd signature cannot silently no-op.
do $$
declare
	_fn text;
	_sig text;
	-- Steps of an authorized RPC, never entry points. No authorization of their
	-- own; the caller is expected to have done it. Nobody but the owner may call.
	_internal text[] := array[
		'_move_tokens', '_welcome_volunteer', '_notify_new_volunteer'
	];
	-- Invoked by a trigger, never called directly.
	_triggers text[] := array[
		'enforce_submission_author_edits', 'handle_new_scholar', 'log_audit_event',
		'log_token_event', 'send_email', 'venue_needs_address_to_activate'
	];
	-- Operational, and reachable only by the service role that runs the crons.
	_service_only text[] := array[
		'reconcile_ledger', 'tokens_as_of', 'replay_audit_log', 'site_origin',
		'forget_scholar'
	];
	-- Ordinary RPCs: a signed-in caller, whose authorization each re-implements.
	_authenticated text[] := array[
		'accept_role_invite', 'approve_thanks', 'approve_transaction',
		'approve_venue_proposal', 'bulk_import_submissions', 'complete_assignment',
		'create_submission', 'create_volunteer', 'decline_thanks', 'erase_scholar',
		'export_scholar_data', 'mark_submission_done', 'mint_tokens', 'propose_thanks',
		'queue_email', 'queue_steward_email', 'queue_thanks_emails',
		'request_email_verification', 'scholar_balances', 'set_steward',
		'transfer_tokens'
	];
	-- Callable without a session, deliberately. verify_email is followed from a
	-- link in an email before the recipient has signed in; currency_holder_counts
	-- returns only aggregates (supply and holder COUNTS, never a balance), which
	-- DESIGN.md holds should be public -- "the oversight on supply is the public
	-- ledger". Granted explicitly so each is a decision rather than a leftover.
	_public text[] := array['verify_email', 'currency_holder_counts'];
begin
	for _fn, _sig in
		select p.proname, p.oid::regprocedure::text
		from pg_proc p
		join pg_namespace n on n.oid = p.pronamespace
		where n.nspname = 'public'
			and p.prokind = 'f'
			and p.prosecdef
			and p.proname = any (_internal || _triggers || _service_only || _authenticated || _public)
	loop
		-- Start from nothing in every case, so the grant below is the whole truth
		-- about who may call this function.
		execute format('revoke execute on function %s from public, anon, authenticated', _sig);

		if _fn = any (_authenticated) then
			execute format('grant execute on function %s to authenticated', _sig);
		elsif _fn = any (_public) then
			execute format('grant execute on function %s to anon, authenticated', _sig);
		end if;
		-- _internal, _triggers and _service_only get no grant. service_role keeps
		-- the grant its own schema file gives it; the revoke above names only
		-- public, anon and authenticated.
	end loop;
end $$;
