alter table "public"."venues"
add column "inactive" text default 'This venue is being configured.'::text;
