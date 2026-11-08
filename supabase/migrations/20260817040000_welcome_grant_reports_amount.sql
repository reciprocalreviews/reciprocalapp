-- Report how many welcome tokens a volunteer actually received.
--
-- The volunteer confirmation told every scholar they would "receive welcome
-- tokens once the minter approves them" — wrong twice over now: grants settle
-- immediately, and three conditions decide whether a grant happens at all
-- (this must be the scholar's first role, the venue must not be payment-free,
-- and welcome_amount must be positive). The client cannot evaluate those
-- reliably, and re-deriving them there would put the rule in two places, so
-- the RPCs report the outcome instead.
--
-- _welcome_volunteer returns the number of tokens granted, 0 on each of its
-- no-op paths. Postgres refuses a return-type change through
-- `create or replace`, so the function is dropped first; both callers are
-- recreated below to capture the value into their result.

drop function if exists public._welcome_volunteer (uuid, uuid, uuid, text);

create function public._welcome_volunteer (
	_welcomer uuid,
	_scholar uuid,
	_roleid uuid,
	_reason text
) returns integer language plpgsql security definer
set
	search_path = public, pg_temp as $function$
declare
	_venue public.venues;
	_txn_id uuid;
	_available integer;
	_shortfall integer;
	_token_ids uuid[];
begin
	-- Find the venue that owns the role being volunteered for.
	select v.* into _venue
	from public.venues v
	join public.roles r on r.id = _roleid
	where v.id = r.venueid;
	-- Role or venue gone? Nothing to grant.
	if not found then
		return 0;
	end if;

	-- Payment-free venues have no tokens, and a zero welcome amount means there
	-- is nothing to grant — either way, do nothing.
	if _venue.payment_free or _venue.welcome_amount <= 0 then
		return 0;
	end if;

	-- Attribute both token writes below (the shortfall mint and the transfer) to
	-- the transaction recorded at the end. The id is generated up front because
	-- the tokens are written before the transaction row exists, and the
	-- token_events trigger reads app.txn at the moment of the write.
	_txn_id := gen_random_uuid();
	perform set_config('app.txn', _txn_id::text, true);

	-- Draw from the venue's reserve, minting only the shortfall into it first —
	-- the same shape approve_transaction gives a venue-sourced transfer.
	select count(*) into _available
	from public.tokens
	where currency = _venue.currency and venue = _venue.id;
	_shortfall := greatest(0, _venue.welcome_amount - _available);
	if _shortfall > 0 then
		insert into public.tokens (currency, venue, scholar)
		select _venue.currency, _venue.id, null from generate_series(1, _shortfall);
	end if;

	-- Choose the granted tokens and move them to the scholar.
	select array_agg(id) into _token_ids
	from (
		select id from public.tokens
		where currency = _venue.currency and venue = _venue.id
		order by id
		limit _venue.welcome_amount
	) sub;
	update public.tokens set venue = null, scholar = _scholar where id = any(_token_ids);

	-- Record the settled grant as one approved venue->scholar transaction.
	insert into public.transactions (
		id, creator, from_scholar, from_venue, to_scholar, to_venue,
		tokens, currency, purpose, status
	) values (
		_txn_id, _welcomer, null, _venue.id, _scholar, null,
		_token_ids, _venue.currency, _reason, 'approved'
	);

	-- Clear the attribution, so a later token write in this same database
	-- transaction that is NOT part of this grant is recorded as unattributed
	-- rather than borrowing this transaction's id.
	perform set_config('app.txn', '', true);

	-- Report what was granted, so the caller can say so precisely.
	return cardinality(_token_ids);
end;
$function$;

revoke execute on function public._welcome_volunteer (uuid, uuid, uuid, text) from public;

-- create_volunteer: now reports the welcome grant alongside the volunteer id.
create or replace function public.create_volunteer (
	_scholarid uuid,
	_roleid uuid,
	_accepted boolean,
	_compensate boolean,
	_papers integer
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
declare
	_caller uuid;
	_venueid uuid;
	_invited boolean;
	_existing_count integer;
	_volunteer_id uuid;
	_granted integer := 0;
begin
	-- Identify and require an authenticated caller.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- Look up the role's venue and whether it is invite-only.
	select venueid, invited into _venueid, _invited from public.roles where id = _roleid;
	if _venueid is null then
		raise exception 'Role not found';
	end if;

	-- A venue admin may add anyone; otherwise a scholar may only add themselves,
	-- and only to a role that is not invite-only.
	if not (public.isAdmin(_venueid) or (_caller = _scholarid and not _invited)) then
		raise exception 'You are not authorized to volunteer for this role';
	end if;

	-- No duplicate volunteering for the same role. RR004 surfaces the specific
	-- "already volunteered" message.
	if exists (select 1 from public.volunteers where scholarid = _scholarid and roleid = _roleid) then
		raise exception 'Already volunteered for this role' using errcode = 'RR004';
	end if;

	-- Welcome tokens are granted only once, on the scholar's very first role, so
	-- count their existing volunteer rows before inserting the new one.
	select count(*) into _existing_count from public.volunteers where scholarid = _scholarid;

	-- Create the volunteer record.
	insert into public.volunteers (scholarid, roleid, active, accepted, expertise, papers)
	values (
		_scholarid, _roleid, _accepted,
		case when _accepted then 'accepted'::public.invited else 'invited'::public.invited end,
		'', _papers
	) returning id into _volunteer_id;

	-- First role and compensation requested? Settle the welcome grant in the
	-- same transaction, so the volunteer can never exist without it.
	if _existing_count = 0 and _compensate then
		_granted := public._welcome_volunteer(_caller, _scholarid, _roleid, 'Welcome tokens for volunteering');
	end if;

	-- Return the new volunteer id and what the grant actually came to.
	return jsonb_build_object('volunteer_id', _volunteer_id, 'welcome_granted', _granted);
end;
$function$;

revoke execute on function public.create_volunteer (uuid, uuid, boolean, boolean, integer) from public;
grant execute on function public.create_volunteer (uuid, uuid, boolean, boolean, integer) to authenticated;

-- accept_role_invite: likewise reports the grant, so accepting an invitation
-- can finally say something (it was silent before).
create or replace function public.accept_role_invite (
	_volunteer_id uuid,
	_response public.invited
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
declare
	_caller uuid;
	_v public.volunteers;
	_total integer;
	_granted integer := 0;
begin
	-- Identify and require an authenticated caller.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- Load the invitation; only the invited scholar may respond to it.
	select * into _v from public.volunteers where id = _volunteer_id;
	if not found then
		raise exception 'Volunteer record not found';
	end if;
	if _caller <> _v.scholarid then
		raise exception 'You can only respond to your own invitations';
	end if;

	-- Count the scholar's volunteer rows to detect a first-role acceptance.
	select count(*) into _total from public.volunteers where scholarid = _v.scholarid;

	-- Apply the response and (re)activate the record.
	update public.volunteers set active = true, accepted = _response where id = _volunteer_id;

	-- Accepting a first invitation earns the welcome grant, recorded atomically.
	if _total = 1 and _v.accepted = 'invited' and _response = 'accepted' then
		_granted := public._welcome_volunteer(_v.scholarid, _v.scholarid, _v.roleid, 'Welcome tokens for accepting role invite');
	end if;

	-- Return the volunteer id that was updated and what the grant came to.
	return jsonb_build_object('volunteer_id', _volunteer_id, 'welcome_granted', _granted);
end;
$function$;

revoke execute on function public.accept_role_invite (uuid, public.invited) from public;
grant execute on function public.accept_role_invite (uuid, public.invited) to authenticated;
