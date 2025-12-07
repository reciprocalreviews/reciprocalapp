alter table "public"."assignments"
add column "created_at" timestamp with time zone not null default timezone ('utc'::text, now());

alter table "public"."scholars"
rename column "when" to "created_at";

alter table "public"."supporters"
rename column "created" to "created_at";

alter table "public"."transactions"
rename column "created" to "created_at";

alter table "public"."volunteers"
rename column "created" to "created_at";
