-- Let a venue be approved before its community has found a minter.
--
-- WHY
--
-- `approve_venue_proposal` required every proposed editor AND minter address to already
-- match a `scholars.email`, or it raised and rolled the whole approval back. That put the
-- hardest requirement at the earliest moment: a community adopting the platform frequently
-- has not identified an independent minter yet, and could not get a venue at all until it
-- had. The failure also landed on a steward pressing Approve, possibly weeks after the
-- proposal was filed, as an opaque "couldn't create the venue".
--
-- Three things already in the schema make a better arrangement possible:
--
--   1. Approval has never meant launch. `venues.inactive` defaults to 'This venue is being
--      configured.' and this function never cleared it.
--   2. A venue runs without a human minter. `_welcome_volunteer` settles welcome grants
--      itself ("no per-grant minter approval is required"), so volunteers can join and be
--      paid; a minter is needed only to top the reserve up later, or to exchange.
--   3. A placeholder minter already existed — the payment-free branch below has always made
--      the approving steward the sole minter of the hidden currency.
--
-- So: approval takes whoever has an account and never blocks on minters, and the separation
-- that actually matters is enforced where it matters, at launch (20260828000010).
--------------------------------------
create or replace function public.approve_venue_proposal (_proposal_id uuid) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_proposal public.proposals;
	_editor_ids uuid[];
	_minter_ids uuid[];
	_currency uuid;
	_venue uuid;
	_role uuid;
	_submission_type uuid;
	_editor uuid;
	_supporter_ids uuid[];
begin
	-- Only an authenticated steward may approve a proposal.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	if not public.isSteward() then
		raise exception 'Only stewards can approve venue proposals';
	end if;

	-- Load the proposal being approved.
	select * into _proposal from public.proposals where id = _proposal_id;
	if not found then
		raise exception 'Proposal not found';
	end if;

	-- Resolve the proposed editor emails to scholar ids, taking whoever has an account
	-- rather than demanding all of them. An editor who has not signed up yet was emailed an
	-- invitation when the proposal was filed and can be added later; requiring them up front
	-- would mean that invitation could only ever reach people who did not need it. At least
	-- one is a hard floor: venues_admins_check forbids a venue with no admins.
	select array_agg(id) into _editor_ids from public.scholars where email = any(_proposal.editors);
	if _editor_ids is null then
		raise exception 'No proposed editors have accounts' using errcode = 'RR014';
	end if;

	-- Determine the venue's currency, creating one if the proposal didn't name
	-- an existing currency to share.
	_currency := _proposal.currency;
	if _currency is null then
		if _proposal.payment_free then
			-- A payment-free venue still needs a (hidden) currency, but no minters
			-- were proposed, so the approving steward holds it.
			_minter_ids := array[_caller];
		else
			-- Whoever has an account mints; if nobody does, the approving steward holds the
			-- currency until the venue names someone. currencies_minters_check requires at
			-- least one, and a community adopting the platform often has not found an
			-- independent minter yet — refusing the venue until it has is the barrier this
			-- replaces. The steward may also be one of the editors above, and so an admin of
			-- this venue: that overlap is tolerated only while the venue is inactive, and
			-- mint_tokens refuses to mint into a venue the caller administers regardless.
			select array_agg(id) into _minter_ids from public.scholars where email = any(_proposal.minters);
			if _minter_ids is null then
				_minter_ids := array[_caller];
			end if;
		end if;
		insert into public.currencies (name, minters)
		values (_proposal.title || ' currency', _minter_ids)
		returning id into _currency;
	end if;

	-- Create the venue with the editors as admins. Paying venues start with a
	-- welcome amount of 10; payment-free venues grant nothing.
	insert into public.venues (title, url, admins, welcome_amount, currency, payment_free)
	values (
		_proposal.title, _proposal.url, _editor_ids,
		case when _proposal.payment_free then 0 else 10 end,
		_currency, _proposal.payment_free
	) returning id into _venue;

	-- Link the proposal to the venue it produced.
	update public.proposals set venue = _venue where id = _proposal_id;

	-- Create the default Editor role for the venue.
	insert into public.roles (venueid, invited, name, description)
	values (
		_venue, true, 'Editor',
		'Triages submissions, assigns meta-reviewers, and makes final decisions on submissions.'
	) returning id into _role;

	-- Enroll every editor as an accepted volunteer in that role.
	foreach _editor in array _editor_ids loop
		insert into public.volunteers (scholarid, roleid, active, accepted, expertise, papers)
		values (_editor, _role, true, 'accepted', '', null);
	end loop;

	-- Create the default submission type (zero cost for payment-free venues).
	insert into public.submission_types (venue, name, description, revision_of, submission_cost)
	values (
		_venue, 'Research Article', 'The default submission type for this venue.', null,
		case when _proposal.payment_free then 0 else 10 end
	) returning id into _submission_type;

	-- Paying venues compensate the Editor role for the default submission type.
	if not _proposal.payment_free then
		insert into public.compensation (submission_type, role, amount, rationale)
		values (
			_submission_type, _role, 1,
			'It takes some time to triage a new submission and make a decision.'
		);
	end if;

	-- Gather the proposal's supporters so the application layer can email them
	-- (alongside the editors) that the venue was approved.
	select array_agg(scholarid) into _supporter_ids from public.supporters where proposalid = _proposal_id;

	-- Return the new venue plus the ids the caller needs for notifications.
	return jsonb_build_object(
		'venue_id', _venue,
		'editor_ids', to_jsonb(_editor_ids),
		'supporter_ids', to_jsonb(coalesce(_supporter_ids, array[]::uuid[])),
		'title', _proposal.title
	);
end;
$function$;
