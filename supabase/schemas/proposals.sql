--------------------------------------
-- Schema
-- Represents a proposal for a venue to be supported.
create table if not exists "public"."proposals" (
	-- The unique ID of the venue
	id uuid default "gen_random_uuid" () not null,
	-- The title of the venue
	title text default ''::"text" not null,
	-- A link to the venue's official web page
	url text default ''::"text" not null,
	-- The email addresses of editors responsible for the venue
	editors text[] default '{}'::"text" [] not null,
	-- The email addresses of minters for the new currency
	minters text[] default '{}'::"text" [] not null,
	-- The id of the existing currency to use for the venue, if any
	currency uuid,
	-- The estimated size of the research community,
	census integer not null,
	-- Whether the proposed venue should operate without payment. When true,
	-- approval skips the minter requirement and auto-creates a hidden currency.
	payment_free boolean default false not null,
	-- If set, corresponds to the venue created upon approval.
	venue uuid
);

alter table "public"."proposals" OWNER to "postgres";

alter table only "public"."proposals"
add constraint "proposals_currency_fkey" foreign KEY ("currency") references "public"."currencies" ("id");

alter table only "public"."proposals"
add constraint "proposals_venue_fkey" foreign KEY ("venue") references "public"."venues" ("id");

alter table only "public"."proposals"
add constraint "proposals_pkey" primary key ("id");

--------------------------------------
-- Security
alter table "public"."proposals" ENABLE row LEVEL SECURITY;

create policy "anyone can view proposals" on "public"."proposals" for
select
	to authenticated,
	anon using (true);

create policy "anyone can propose venues" on "public"."proposals" for INSERT to authenticated
with
	check (true);

create policy "admins can update proposals" on "public"."proposals"
for update
	to authenticated using (public.isSteward ());

create policy "admins can delete proposals" on "public"."proposals" for DELETE to authenticated using (public.isSteward ());

--------------------------------------
-- RPCs (defined in migration 20260608000000_atomic_crud.sql)
-- approve_venue_proposal: provision a whole venue from an approved proposal —
-- currency (if none was proposed), venue, editor role, editor volunteers,
-- default submission type, and default compensation — and link the proposal to
-- the new venue, all atomically, so a partial failure can't orphan records.
-- SECURITY DEFINER; stewards only. Emails to editors and supporters are
-- dispatched by the application layer from the returned ids.
create or replace function public.approve_venue_proposal (
	_proposal_id uuid
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
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

	-- Resolve the proposed editor emails to scholar ids; every editor must
	-- already have an account.
	select array_agg(id) into _editor_ids from public.scholars where email = any(_proposal.editors);
	if _editor_ids is null or cardinality(_editor_ids) < cardinality(_proposal.editors) then
		raise exception 'Not all proposed editors have accounts';
	end if;

	-- Determine the venue's currency, creating one if the proposal didn't name
	-- an existing currency to share.
	_currency := _proposal.currency;
	if _currency is null then
		if _proposal.payment_free then
			-- A payment-free venue still needs a (hidden) currency, but no minters
			-- were proposed. The approving steward becomes the sole minter —
			-- stewards are never venue admins, so no_admin_minters passes.
			_minter_ids := array[_caller];
		else
			-- Resolve the proposed minter emails; every minter must have an account.
			select array_agg(id) into _minter_ids from public.scholars where email = any(_proposal.minters);
			if _minter_ids is null or cardinality(_minter_ids) < cardinality(_proposal.minters) then
				raise exception 'Not all proposed minters have accounts';
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

revoke execute on function public.approve_venue_proposal (uuid) from public;
grant execute on function public.approve_venue_proposal (uuid) to authenticated;

grant all on table "public"."proposals" to "anon";

grant all on table "public"."proposals" to "authenticated";

grant all on table "public"."proposals" to "service_role";

alter publication supabase_realtime
add table proposals;
