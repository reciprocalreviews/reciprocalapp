--------------------------------------
-- Schema
-- Represents a proposal for a venue to be supported.
create table if not exists "public"."proposals" (
	-- The unique ID of the venue
	"id" "uuid" default "gen_random_uuid" () not null,
	-- The title of the venue
	"title" "text" default ''::"text" not null,
	-- A link to the venue's official web page
	"url" "text" default ''::"text" not null,
	-- The email addresses of editors responsible for the venue
	"editors" "text" [] default '{}'::"text" [] not null,
	-- The email addresses of minters for the new currency
	"minters" "text" [] default '{}'::"text" [] not null,
	-- The id of the existing currency to use for the venue, if any
	"currency" "uuid",
	-- The estimated size of the research community,
	"census" integer not null,
	-- If set, corresponds to the venue created upon approval.
	"venue" "uuid"
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
	to "authenticated",
	"anon" using (true);

create policy "anyone can propose venues" on "public"."proposals" for INSERT to "authenticated",
"anon"
with
	check (true);

create policy "admins can update proposals" on "public"."proposals"
for update
	to "authenticated",
	"anon" using ("public"."issteward" ());

create policy "admins can delete proposals" on "public"."proposals" for DELETE to "authenticated",
"anon" using ("public"."issteward" ());

grant all on table "public"."proposals" to "anon";

grant all on table "public"."proposals" to "authenticated";

grant all on table "public"."proposals" to "service_role";
