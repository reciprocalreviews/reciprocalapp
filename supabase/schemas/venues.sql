--------------------------------------
-- Schema
create table if not exists "public"."venues" (
	-- The unique ID of the venue
	"id" "uuid" default "gen_random_uuid" () not null,
	-- The title of the venue
	"title" "text" default ''::"text" not null,
	-- The description of the venue
	"description" "text" default ''::"text" not null,
	-- A link to the venue's official web page
	"url" "text" default ''::"text" not null,
	-- The id of the currency the venue is currently using
	"currency" "uuid" not null,
	-- The optional amount of newly minted tokens granted to new volunteers
	"welcome_amount" integer not null,
	-- The amount of tokens granted for each submission for an editor.
	"edit_amount" integer default 1 not null,
	-- Submission cost in the venue's currency
	"submission_cost" integer default 0 not null,
	-- One or more scholars who serve as editors of the venue
	"editors" "uuid" [] default '{}'::"uuid" [] not null,
	-- There must be at least one editor
	constraint "venues_editors_check" check (("cardinality" ("editors")>0))
);

alter table only "public"."venues"
add constraint "venues_pkey" primary key ("id");

alter table only "public"."venues"
add constraint "venues_currency_fkey" foreign KEY ("currency") references "public"."currencies" ("id");

--------------------------------------
-- Security
alter table "public"."venues" OWNER to "postgres";

alter table "public"."venues" ENABLE row LEVEL SECURITY;

create policy "anyone can view venues" on "public"."venues" for
select
	to "authenticated",
	"anon" using (true);

create policy "only stewards can create venues" on "public"."venues" for INSERT to "authenticated",
"anon"
with
	check ("public"."issteward" ());

create policy "stewards and editors can update venues" on "public"."venues"
for update
	to "authenticated",
	"anon" using (
		(
			"public"."issteward" ()
			or (
				(
					select
						"auth"."uid" () as "uid"
				)=any ("editors")
			)
		)
	);

create policy "stewards and editors can delete venues" on "public"."venues" for DELETE to "authenticated",
"anon" using (
	(
		"public"."issteward" ()
		or (
			(
				select
					"auth"."uid" () as "uid"
			)=any ("editors")
		)
	)
);

grant all on table "public"."venues" to "anon";

grant all on table "public"."venues" to "authenticated";

grant all on table "public"."venues" to "service_role";

--------------------------------------
-- Security
create or replace function "public"."no_minter_editors" () RETURNS "trigger" LANGUAGE "plpgsql" SECURITY DEFINER
set
	"search_path" to '' as $$
begin
    -- If the editor of this venue is a minter of its currency, raise an exception
    if new.editors && (select minters from public.currencies where id = new.currency) then
        raise exception 'A venue editor cannot be the minter of the venue currency';
    end if;
    return new;
end;
$$;

alter function "public"."no_minter_editors" () OWNER to "postgres";

grant all on FUNCTION "public"."no_minter_editors" () to "anon";

grant all on FUNCTION "public"."no_minter_editors" () to "authenticated";

grant all on FUNCTION "public"."no_minter_editors" () to "service_role";

--------------------------------------
-- Trigger
create or replace trigger "no_minter_editors" BEFORE INSERT
or
update on "public"."venues" for EACH row
execute FUNCTION "public"."no_minter_editors" ();
