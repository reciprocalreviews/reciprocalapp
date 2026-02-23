create table "public"."compensation" (
	"submission_type" uuid not null,
	"role" uuid not null,
	"amount" integer,
	"rationale" text not null default ''::text
);

alter table "public"."compensation" enable row level security;

create table "public"."submission_types" (
	"id" uuid not null default gen_random_uuid(),
	"venue" uuid not null,
	"revision_of" uuid,
	"name" text not null default ''::text,
	"description" text not null default ''::text
);

alter table "public"."submission_types" enable row level security;

alter table "public"."roles"
drop column "amount";

create unique index compensation_pkey on public.compensation using btree (submission_type, role);

create unique index submission_types_pkey on public.submission_types using btree (id);

create index submission_types_venue_index on public.submission_types using btree (venue);

alter table "public"."compensation"
add constraint "compensation_pkey" primary key using index "compensation_pkey";

alter table "public"."submission_types"
add constraint "submission_types_pkey" primary key using index "submission_types_pkey";

alter table "public"."compensation"
add constraint "compensation_role_fkey" foreign KEY (role) references public.roles (id) on delete cascade not valid;

alter table "public"."compensation" validate constraint "compensation_role_fkey";

alter table "public"."compensation"
add constraint "compensation_submission_type_fkey" foreign KEY (submission_type) references public.submission_types (id) on delete cascade not valid;

alter table "public"."compensation" validate constraint "compensation_submission_type_fkey";

alter table "public"."submission_types"
add constraint "submission_types_revision_of_fkey" foreign KEY (revision_of) references public.submission_types (id) on delete cascade not valid;

alter table "public"."submission_types" validate constraint "submission_types_revision_of_fkey";

alter table "public"."submission_types"
add constraint "submission_types_venue_fkey" foreign KEY (venue) references public.venues (id) on delete cascade not valid;

alter table "public"."submission_types" validate constraint "submission_types_venue_fkey";

grant delete on table "public"."compensation" to "anon";

grant insert on table "public"."compensation" to "anon";

grant references on table "public"."compensation" to "anon";

grant
select
	on table "public"."compensation" to "anon";

grant trigger on table "public"."compensation" to "anon";

grant
truncate on table "public"."compensation" to "anon";

grant
update on table "public"."compensation" to "anon";

grant delete on table "public"."compensation" to "authenticated";

grant insert on table "public"."compensation" to "authenticated";

grant references on table "public"."compensation" to "authenticated";

grant
select
	on table "public"."compensation" to "authenticated";

grant trigger on table "public"."compensation" to "authenticated";

grant
truncate on table "public"."compensation" to "authenticated";

grant
update on table "public"."compensation" to "authenticated";

grant delete on table "public"."compensation" to "service_role";

grant insert on table "public"."compensation" to "service_role";

grant references on table "public"."compensation" to "service_role";

grant
select
	on table "public"."compensation" to "service_role";

grant trigger on table "public"."compensation" to "service_role";

grant
truncate on table "public"."compensation" to "service_role";

grant
update on table "public"."compensation" to "service_role";

grant delete on table "public"."submission_types" to "anon";

grant insert on table "public"."submission_types" to "anon";

grant references on table "public"."submission_types" to "anon";

grant
select
	on table "public"."submission_types" to "anon";

grant trigger on table "public"."submission_types" to "anon";

grant
truncate on table "public"."submission_types" to "anon";

grant
update on table "public"."submission_types" to "anon";

grant delete on table "public"."submission_types" to "authenticated";

grant insert on table "public"."submission_types" to "authenticated";

grant references on table "public"."submission_types" to "authenticated";

grant
select
	on table "public"."submission_types" to "authenticated";

grant trigger on table "public"."submission_types" to "authenticated";

grant
truncate on table "public"."submission_types" to "authenticated";

grant
update on table "public"."submission_types" to "authenticated";

grant delete on table "public"."submission_types" to "service_role";

grant insert on table "public"."submission_types" to "service_role";

grant references on table "public"."submission_types" to "service_role";

grant
select
	on table "public"."submission_types" to "service_role";

grant trigger on table "public"."submission_types" to "service_role";

grant
truncate on table "public"."submission_types" to "service_role";

grant
update on table "public"."submission_types" to "service_role";

create policy "anyone can read compensation" on "public"."compensation" as permissive for
select
	to authenticated using (true);

create policy "venue admins can delete compensation" on "public"."compensation" as permissive for delete to authenticated using (
	public.isadmin (
		(
			select
				roles.venueid
			from
				public.roles
			where
				(roles.id=compensation.role)
		)
	)
);

create policy "venue admins can insert compensation" on "public"."compensation" as permissive for insert to authenticated
with
	check (
		public.isadmin (
			(
				select
					roles.venueid
				from
					public.roles
				where
					(roles.id=compensation.role)
			)
		)
	);

create policy "venue admins can update compensation" on "public"."compensation" as permissive
for update
	to authenticated using (
		public.isadmin (
			(
				select
					roles.venueid
				from
					public.roles
				where
					(roles.id=compensation.role)
			)
		)
	)
with
	check (true);

create policy "anyone can read submission types" on "public"."submission_types" as permissive for
select
	to authenticated using (true);

create policy "venue admins can create submission types" on "public"."submission_types" as permissive for insert to authenticated
with
	check (public.isadmin (venue));

create policy "venue admins can delete submission types" on "public"."submission_types" as permissive for delete to authenticated using (public.isadmin (venue));

create policy "venue admins can update submission types" on "public"."submission_types" as permissive
for update
	to authenticated using (public.isadmin (venue))
with
	check (true);

alter table "public"."submissions"
add column "submission_type" uuid not null references "public"."submission_types" (id);
