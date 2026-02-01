drop extension if exists "pg_cron";

drop trigger if exists "no_editor_minters" on "public"."currencies";

drop policy "admins can update submissions" on "public"."submissions";

alter table "public"."assignments"
drop constraint "assignments_role_fkey";

alter table "public"."assignments"
drop constraint "assignments_scholar_fkey";

alter table "public"."assignments"
drop constraint "assignments_submission_fkey";

alter table "public"."assignments"
drop constraint "assignments_venue_fkey";

drop function if exists "public"."no_editor_minters" ();

alter table "public"."assignments"
add constraint "assignments_role_fkey" foreign KEY (role) references public.roles (id) on delete cascade not valid;

alter table "public"."assignments" validate constraint "assignments_role_fkey";

alter table "public"."assignments"
add constraint "assignments_scholar_fkey" foreign KEY (scholar) references public.scholars (id) on delete cascade not valid;

alter table "public"."assignments" validate constraint "assignments_scholar_fkey";

alter table "public"."assignments"
add constraint "assignments_submission_fkey" foreign KEY (submission) references public.submissions (id) on delete cascade not valid;

alter table "public"."assignments" validate constraint "assignments_submission_fkey";

alter table "public"."assignments"
add constraint "assignments_venue_fkey" foreign KEY (venue) references public.venues (id) on delete cascade not valid;

alter table "public"."assignments" validate constraint "assignments_venue_fkey";

set
	check_function_bodies=off;

create or replace function public.no_admin_minters () RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
set
	search_path to '' as $function$
begin
    -- If the admin of this venue is a minter of its currency, raise an exception
    if exists (select * from public.venues where public.venues.currency = new.id and (public.venues.admins && new.minters)) then
        raise exception 'A venue minter cannot be the admin of the venue currency';
    end if;
    return new;
end;
$function$;

create policy "authors and editors can update submissions" on "public"."submissions" as permissive
for update
	to authenticated using (
		(
			(
				exists (
					select
						assignments.id
					from
						public.assignments
					where
						(
							(assignments.submission=assignments.id)
							and (
								assignments.scholar=(
									select
										auth.uid () as uid
								)
							)
							and (assignments.approved=true)
							and (
								exists (
									select
										roles.id
									from
										public.roles
									where
										(
											(roles.id=assignments.role)
											and (roles.priority=0)
										)
								)
							)
						)
				)
			)
			or (
				(
					select
						auth.uid () as uid
				)=any (authors)
			)
		)
	);

create trigger no_admin_minters BEFORE
update on public.currencies for EACH row
execute FUNCTION public.no_admin_minters ();
