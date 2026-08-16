--------------------------------------
-- Schema
create table if not exists "public"."currencies" (
	-- The unique id of the currency
	id uuid default "gen_random_uuid" () not null,
	-- The name of the currency
	name text default ''::"text" not null,
	-- The description of the currency
	description text default ''::"text" not null,
	-- The minters of the currency, corresponding to scholar is in the scholars table. Must be at least one minter.
	minters uuid[] default '{}'::"uuid" [] not null,
	constraint currencies_minters_check check (("cardinality" ("minters")>0))
);

alter table "public"."currencies" OWNER to "postgres";

grant all on table "public"."currencies" to "anon";

grant all on table "public"."currencies" to "authenticated";

grant all on table "public"."currencies" to "service_role";

-- `grant all` above confers TABLE-level DELETE; deletion is denied to clients
-- (see the deny policy below), so remove the privilege as well.
revoke delete on public.currencies
from
	authenticated,
	anon;

alter table only "public"."currencies"
add constraint "currencies_pkey" primary key ("id");

--------------------------------------
-- Security
alter table "public"."currencies" ENABLE row LEVEL SECURITY;

create policy "only stewards can create currencies" on "public"."currencies" for INSERT to authenticated
with
	check ("public"."issteward" ());

create policy "anyone can view currencies" on "public"."currencies" for
select
	to "authenticated",
	"anon" using (true);

-- No client path deletes a currency; its tokens and transactions must outlive
-- any attempt. service_role keeps its grant for administrative and recovery work.
create policy "currencies cannot be deleted" on public.currencies for DELETE to authenticated using (false);

create policy "minters can update currencies" on "public"."currencies"
for update
	to authenticated using (
		(
			(
				select
					"auth"."uid" () as "uid"
			)=any ("minters")
		)
	);

--------------------------------------
-- Functions
create or replace function "public"."no_admin_minters" () RETURNS "trigger" LANGUAGE "plpgsql" SECURITY DEFINER
set
	"search_path" to '' as $$
begin
    -- Payment-free venues never mint or pay, so the anti-self-dealing rule
    -- does not apply; their hidden currency may be minted by an admin.
    if exists (select * from public.venues where public.venues.currency = new.id and (public.venues.admins && new.minters) and not public.venues.payment_free) then
        raise exception 'A venue minter cannot be the admin of the venue currency';
    end if;
    return new;
end;
$$;

alter function "public"."no_admin_minters" () OWNER to "postgres";

grant all on FUNCTION "public"."no_admin_minters" () to "anon";

grant all on FUNCTION "public"."no_admin_minters" () to "authenticated";

grant all on FUNCTION "public"."no_admin_minters" () to "service_role";

--------------------------------------
-- Triggers
--------------------------------------
-- The mirror of venues.no_minter_admins: that one stops a venue gaining an admin
-- who mints its currency; this one stops a currency gaining a minter who
-- administers a venue using it. Both are needed, since either table can be edited
-- independently. The function it calls is declared once, above; it used to be
-- declared twice in this file with identical bodies, and the second copy — the
-- one Postgres actually kept — was the one missing the payment-free rationale.
create or replace trigger "no_admin_minters" BEFORE
update on "public"."currencies" for EACH row
execute FUNCTION "public"."no_admin_minters" ();

alter publication supabase_realtime
add table currencies;
