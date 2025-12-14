drop policy "editors, assignees, and approvers can see assignments" on "public"."assignments";

create or replace function public.isassigned (_submissionid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER
set
	search_path to '' as $function$
	select (exists (select id from public.assignments where submission=_submissionid and scholar=(select auth.uid()) and approved=true))
$function$;

create policy "editors, assignees, and approvers can see assignments" on "public"."assignments" as permissive for
select
	to authenticated,
	anon using (
		(
			public.iseditor (venue)
			or (
				scholar=(
					select
						auth.uid () as uid
				)
			)
			or public.isassigned (submission)
			or public.isapprover (role)
		)
	);
