--------------------------------------
-- Schema
create table if not exists "public"."supporters" (
	-- The unique ID of the support
	id uuid default gen_random_uuid() not null,
	-- The scholar supporting the proposal
	scholarid uuid not null,
	-- The message the scholar supported
	message text default ''::text not null,
	-- The proposal being supported
	proposalid uuid not null,
	-- When this record was last updated
	created_at timestamp with time zone default now() not null
);

alter table "public"."supporters" OWNER to "postgres";

alter table only "public"."supporters"
add constraint "supporters_pkey" primary key ("id");

alter table only "public"."supporters"
add constraint "supporters_proposalid_fkey" foreign KEY ("proposalid") references "public"."proposals" ("id") on delete cascade;

alter table only "public"."supporters"
add constraint "supporters_scholarid_fkey" foreign KEY ("scholarid") references "public"."scholars" ("id") on delete cascade;

--------------------------------------
-- Security
alter table "public"."supporters" ENABLE row LEVEL SECURITY;

create policy "anyone can view supporters" on "public"."supporters" for
select
	to "authenticated",
	"anon" using (true);

create policy "anyone can support proposals" on "public"."supporters" for INSERT to "authenticated"
with
	check (true);

create policy "admins can update proposals" on "public"."supporters"
for update
	to "authenticated",
	"anon" using (
		(
			(
				select
					"auth"."uid" () as "uid"
			)="scholarid"
		)
	);

create policy "supporters can stop supporting" on "public"."supporters" for DELETE to "authenticated",
"anon" using (
	(
		(
			select
				"auth"."uid" () as "uid"
		)="scholarid"
	)
);

grant all on table "public"."supporters" to "anon";

grant all on table "public"."supporters" to "authenticated";

grant all on table "public"."supporters" to "service_role";
