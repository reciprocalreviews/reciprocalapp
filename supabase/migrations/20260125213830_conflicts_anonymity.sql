create table "public"."conflicts" (
	"submissionid" uuid not null,
	"scholarid" uuid not null,
	"reason" text not null default ''::text
);

alter table "public"."conflicts" enable row level security;

alter table "public"."roles"
add column "anonymous_authors" boolean not null default true;

alter table "public"."venues"
add column "anonymous_assignments" boolean not null default true;

create unique index conflicts_pkey on public.conflicts using btree (submissionid, scholarid);

alter table "public"."conflicts"
add constraint "conflicts_pkey" primary key using index "conflicts_pkey";

alter table "public"."conflicts"
add constraint "conflicts_scholarid_fkey" foreign KEY (scholarid) references public.scholars (id) not valid;

alter table "public"."conflicts" validate constraint "conflicts_scholarid_fkey";

alter table "public"."conflicts"
add constraint "conflicts_submissionid_fkey" foreign KEY (submissionid) references public.submissions (id) not valid;

alter table "public"."conflicts" validate constraint "conflicts_submissionid_fkey";

grant delete on table "public"."conflicts" to "anon";

grant insert on table "public"."conflicts" to "anon";

grant references on table "public"."conflicts" to "anon";

grant
select
	on table "public"."conflicts" to "anon";

grant trigger on table "public"."conflicts" to "anon";

grant
truncate on table "public"."conflicts" to "anon";

grant
update on table "public"."conflicts" to "anon";

grant delete on table "public"."conflicts" to "authenticated";

grant insert on table "public"."conflicts" to "authenticated";

grant references on table "public"."conflicts" to "authenticated";

grant
select
	on table "public"."conflicts" to "authenticated";

grant trigger on table "public"."conflicts" to "authenticated";

grant
truncate on table "public"."conflicts" to "authenticated";

grant
update on table "public"."conflicts" to "authenticated";

grant delete on table "public"."conflicts" to "service_role";

grant insert on table "public"."conflicts" to "service_role";

grant references on table "public"."conflicts" to "service_role";

grant
select
	on table "public"."conflicts" to "service_role";

grant trigger on table "public"."conflicts" to "service_role";

grant
truncate on table "public"."conflicts" to "service_role";

grant
update on table "public"."conflicts" to "service_role";

create policy "anyone can see conflicts" on "public"."conflicts" as permissive for
select
	to authenticated using (true);

create policy "editors and volunteers can create conflicts" on "public"."conflicts" as permissive for insert to authenticated,
anon
with
	check (
		(
			public.iseditor (
				(
					select
						submissions.venue
					from
						public.submissions
					where
						(submissions.id=conflicts.submissionid)
				)
			)
			or (
				exists (
					select
						volunteers.id,
						volunteers.scholarid,
						volunteers.roleid,
						volunteers.created_at,
						volunteers.expertise,
						volunteers.active,
						volunteers.accepted
					from
						public.volunteers
					where
						(
							(volunteers.scholarid=conflicts.scholarid)
							and (
								volunteers.roleid in (
									select
										roles.id
									from
										public.roles
									where
										(
											roles.venueid=(
												select
													submissions.venue
												from
													public.submissions
												where
													(submissions.id=conflicts.submissionid)
											)
										)
								)
							)
						)
				)
			)
		)
	);

create policy "editors can delete conflicts" on "public"."conflicts" as permissive for delete to authenticated using (
	public.iseditor (
		(
			select
				submissions.venue
			from
				public.submissions
			where
				(submissions.id=conflicts.submissionid)
		)
	)
);

create policy "editors can update conflicts" on "public"."conflicts" as permissive
for update
	to authenticated using (
		public.iseditor (
			(
				select
					submissions.venue
				from
					public.submissions
				where
					(submissions.id=conflicts.submissionid)
			)
		)
	);
