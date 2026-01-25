--------------------------------------
-- Schema
create table if not exists "public"."currencies" (
	-- The unique id of the currency
	"id" "uuid" default "gen_random_uuid" () not null,
	-- The name of the currency
	"name" "text" default ''::"text" not null,
	-- The description of the currency
	"description" "text" default ''::"text" not null,
	-- The minters of the currency, corresponding to scholar is in the scholars table. Must be at least one minter.
	"minters" "uuid" [] default '{}'::"uuid" [] not null,
	constraint "currencies_minters_check" check (("cardinality" ("minters")>0))
);

alter table "public"."currencies" OWNER to "postgres";

grant all on table "public"."currencies" to "anon";

grant all on table "public"."currencies" to "authenticated";

grant all on table "public"."currencies" to "service_role";

alter table only "public"."currencies"
add constraint "currencies_pkey" primary key ("id");

--------------------------------------
-- Security
alter table "public"."currencies" ENABLE row LEVEL SECURITY;

create policy "anyone can create currencies" on "public"."currencies" for INSERT to "authenticated",
"anon"
with
	check ("public"."issteward" ());

create policy "anyone can view currencies" on "public"."currencies" for
select
	to "authenticated",
	"anon" using (true);

create policy "minters can delete currencies" on "public"."currencies" for DELETE to "authenticated",
"anon" using (
	(
		(
			select
				"auth"."uid" () as "uid"
		)=any ("minters")
	)
);

create policy "minters can update currencies" on "public"."currencies"
for update
	to "authenticated",
	"anon" using (
		(
			(
				select
					"auth"."uid" () as "uid"
			)=any ("minters")
		)
	);

--------------------------------------
-- Functions
create or replace function "public"."no_editor_minters" () RETURNS "trigger" LANGUAGE "plpgsql" SECURITY DEFINER
set
	"search_path" to '' as $$
begin
    -- If the editor of this venue is a minter of its currency, raise an exception
    if exists (select * from public.venues where public.venues.currency = new.id and (public.venues.editors && new.minters)) then
        raise exception 'A venue minter cannot be the editor of the venue currency';
    end if;
    return new;
end;
$$;

alter function "public"."no_editor_minters" () OWNER to "postgres";

grant all on FUNCTION "public"."no_editor_minters" () to "anon";

grant all on FUNCTION "public"."no_editor_minters" () to "authenticated";

grant all on FUNCTION "public"."no_editor_minters" () to "service_role";

--------------------------------------
-- Triggers
create or replace trigger "no_editor_minters" BEFORE
update on "public"."currencies" for EACH row
execute FUNCTION "public"."no_editor_minters" ();
