--------------------------------------
-- Schema
create type "public"."exchange_proposal_kind" as enum('create', 'modify', 'merge');

alter type "public"."exchange_proposal_kind" OWNER to "postgres";

-- Agreements between owners of currencies
create table if not exists "public"."exchanges" (
	-- The unique id of the currency
	"id" "uuid" default "gen_random_uuid" () not null,
	-- The time the exchange was created
	"proposed" timestamp with time zone default "now" () not null,
	-- Whether the minters have approved. Only set when all current active minters have approved.
	"approved" timestamp with time zone,
	-- The first currency of the exchange
	"currency_from" "uuid" not null,
	-- The second currenty of the exchange
	"currency_to" "uuid" not null,
	-- The multiplier to convert from currency_from to currency_to
	"ratio" numeric not null,
	-- List of minters who have approved
	"approvers" "uuid" [] default '{}'::"uuid" [] not null,
	-- The kind of exchange
	"kind" "public"."exchange_proposal_kind"
);

alter table only "public"."exchanges"
add constraint "exchanges_pkey" primary key ("id");

alter table only "public"."exchanges"
add constraint "exchanges_currency_from_fkey" foreign KEY ("currency_from") references "public"."currencies" ("id");

alter table only "public"."exchanges"
add constraint "exchanges_currency_to_fkey" foreign KEY ("currency_to") references "public"."currencies" ("id");

create unique index "from_index" on "public"."exchanges" using "btree" ("currency_from");

create unique index "to_index" on "public"."exchanges" using "btree" ("currency_to");

--------------------------------------
-- Functions
create or replace function "public"."isminter" ("_scholarid" "uuid", "_currencyid" "uuid") RETURNS boolean LANGUAGE "sql" SECURITY DEFINER
set
	"search_path" to '' as $$
    select (exists (select id from public.currencies where id = _currencyid and _scholarid = any(minters)));
$$;

alter function "public"."isminter" ("_scholarid" "uuid", "_currencyid" "uuid") OWNER to "postgres";

grant all on FUNCTION "public"."isminter" ("_scholarid" "uuid", "_currencyid" "uuid") to "anon";

grant all on FUNCTION "public"."isminter" ("_scholarid" "uuid", "_currencyid" "uuid") to "authenticated";

grant all on FUNCTION "public"."isminter" ("_scholarid" "uuid", "_currencyid" "uuid") to "service_role";

--------------------------------------
-- Security
alter table "public"."exchanges" OWNER to "postgres";

alter table "public"."exchanges" ENABLE row LEVEL SECURITY;

create policy "anyone can view exchanges" on "public"."exchanges" for
select
	to "authenticated",
	"anon" using (true);

create policy "only minters can create exchanges" on "public"."exchanges" for INSERT to "authenticated",
"anon"
with
	check (
		(
			"public"."isminter" (
				(
					select
						"auth"."uid" () as "uid"
				),
				"currency_from"
			)
			or "public"."isminter" (
				(
					select
						"auth"."uid" () as "uid"
				),
				"currency_to"
			)
		)
	);

create policy "only minters can update exchanges" on "public"."exchanges"
for update
	to "authenticated",
	"anon" using (
		(
			"public"."isminter" (
				(
					select
						"auth"."uid" () as "uid"
				),
				"currency_from"
			)
			or "public"."isminter" (
				(
					select
						"auth"."uid" () as "uid"
				),
				"currency_to"
			)
		)
	);

create policy "only minters can delete exchanges" on "public"."exchanges" for DELETE to "authenticated",
"anon" using (
	(
		"public"."isminter" (
			(
				select
					"auth"."uid" () as "uid"
			),
			"currency_from"
		)
		or "public"."isminter" (
			(
				select
					"auth"."uid" () as "uid"
			),
			"currency_to"
		)
	)
);

grant all on table "public"."exchanges" to "anon";

grant all on table "public"."exchanges" to "authenticated";

grant all on table "public"."exchanges" to "service_role";
