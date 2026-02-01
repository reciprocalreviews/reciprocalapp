drop policy "editors and assignees can delete assignments" on "public"."assignments";

drop policy "editors, approvers, and volunteers can create assignments" on "public"."assignments";

drop policy "editors, assignees, and approvers can see assignments" on "public"."assignments";

drop policy "editors, assignees, and approvers can update assignments" on "public"."assignments";

drop policy "editors and volunteers can create conflicts" on "public"."conflicts";

drop policy "editors can delete conflicts" on "public"."conflicts";

drop policy "editors can update conflicts" on "public"."conflicts";

drop policy "scholars and venue editors can see the emails sent" on "public"."emails";

drop policy "only editors can create venue roles" on "public"."roles";

drop policy "only editors can delete roles" on "public"."roles";

drop policy "only editors can update roles" on "public"."roles";

drop policy "authors, editors, and bidders can view submissions" on "public"."submissions";

drop policy "editors can delete submissions" on "public"."submissions";

drop policy "editors can update submissions" on "public"."submissions";

drop policy "only token owners can update a token" on "public"."tokens";

drop policy "stewards and editors can delete venues" on "public"."venues";

drop policy "stewards and editors can update venues" on "public"."venues";

drop policy "editors and volunteers can delete" on "public"."volunteers";

drop policy "editors can invite and volunteers if not invite only" on "public"."volunteers";

drop policy "only owners can transfer their tokens if approved" on "public"."transactions";

drop policy "only the giver and minters can update transactions" on "public"."transactions";

drop policy "transactions are only visible to minters and those involved" on "public"."transactions";

alter table "public"."venues"
drop constraint "venues_editors_check";

drop function if exists "public"."iseditor" (_venueid uuid);

drop trigger if exists no_minter_editors on "public"."venues" cascade;

drop function if exists "public"."no_minter_editors" ();

alter table "public"."venues"
drop column "edit_amount";

alter table "public"."venues"
rename column editors to admins;

alter table "public"."venues"
add constraint "venues_admins_check" check ((cardinality(admins)>0)) not valid;

alter table "public"."venues" validate constraint "venues_admins_check";

set
	check_function_bodies=off;

create or replace function public.isadmin (_venueid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER
set
	search_path to '' as $function$
    select ((select auth.uid()) = any((select admins from public.venues where id = _venueid)::uuid[]));
$function$;

create or replace function public.no_minter_admins () RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
set
	search_path to '' as $function$
begin
    -- If the admin of this venue is a minter of its currency, raise an exception
    if new.admins && (select minters from public.currencies where id = new.currency) then
        raise exception 'A venue admin cannot be the minter of the venue currency';
    end if;
    return new;
end;
$function$;

create or replace function public.isapprover (_roleid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER
set
	search_path to '' as $function$
    select (
		exists (
			select id 
			from public.volunteers 
			where 
				scholarid = (select auth.uid()) and 
				roleid=(select approver from public.roles where id=_roleid) and 
				accepted = 'accepted'
		)
	)
$function$;

create policy "admins, approvers and volunteers can create assignments" on "public"."assignments" for insert to "authenticated",
"anon"
with
	check (
		(
			-- If the current scholar is an admin, they can create any assignment.
			public.isAdmin (venue)
			-- If the current scholar has an assigment to the role that is the approver for the new assignment's role.
			or (
				isApprover (role)
				and isAssigned (submission)
			)
			-- If the venue permits bidding and the volunteer has the role for which this assignment is being created.
			or (
				bid
				and (
					exists (
						select
						from
							public.volunteers
						where
							(
								(volunteers.roleid=assignments.role)
								and (
									volunteers.scholarid=(
										select
											auth.uid () as "uid"
									)
								)
								and volunteers.active
								and (volunteers.accepted='accepted')
							)
					)
				)
			)
		)
	);

create policy "assignees and approvers can see assignments" on "public"."assignments" as permissive for
select
	to authenticated using (
		(
			(
				(
					select
						venues.anonymous_assignments
					from
						public.venues
					where
						(venues.id=assignments.venue)
				)=false
			)
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

create policy "assignees and approvers can update assignments" on "public"."assignments" as permissive
for update
	to authenticated,
	anon using (
		(
			(
				scholar=(
					select
						auth.uid () as uid
				)
			)
			or public.isapprover (role)
		)
	);

create policy "assignees can delete assignments" on "public"."assignments" as permissive for delete to authenticated using (
	(
		scholar=(
			select
				auth.uid () as uid
		)
	)
);

create policy "admins and volunteers can create conflicts" on "public"."conflicts" as permissive for insert to authenticated,
anon
with
	check (
		(
			public.isadmin (
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

create policy "admins can delete conflicts" on "public"."conflicts" as permissive for delete to authenticated using (
	public.isadmin (
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

create policy "admins can update conflicts" on "public"."conflicts" as permissive
for update
	to authenticated using (
		public.isadmin (
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

create policy "recipients and venue admins can see the emails sent" on "public"."emails" as permissive for
select
	to authenticated,
	anon using (
		(
			(
				(
					select
						auth.uid () as uid
				)=scholar
			)
			or (
				(venue is not null)
				and public.isadmin (venue)
			)
		)
	);

create policy "only admins can create venue roles" on "public"."roles" as permissive for insert to authenticated,
anon
with
	check (public.isadmin (venueid));

create policy "only admins can delete roles" on "public"."roles" as permissive for delete to authenticated,
anon using (public.isadmin (venueid));

create policy "only admins can update roles" on "public"."roles" as permissive
for update
	to authenticated,
	anon using (public.isadmin (venueid));

create policy "admins can delete submissions" on "public"."submissions" as permissive for delete to authenticated using (public.isadmin (venue));

create policy "admins can update submissions" on "public"."submissions" as permissive
for update
	to authenticated using (public.isadmin (venue));

create policy "authors, assigned, and bidders can view submissions" on "public"."submissions" as permissive for
select
	to authenticated,
	anon using (
		(
			(
				(
					select
						auth.uid () as uid
				)=any (authors)
			)
			or (
				exists (
					select
						volunteers.id
					from
						public.volunteers
					where
						(
							(
								volunteers.scholarid=(
									select
										auth.uid () as uid
								)
							)
							and (volunteers.accepted='accepted'::public.invited)
							and (
								volunteers.roleid=any (
									array(
										select
											roles.id
										from
											public.roles
										where
											(
												(roles.venueid=submissions.venue)
												and (roles.biddable=true)
											)
									)
								)
							)
						)
				)
			)
			or (
				exists (
					select
						assignments.id
					from
						public.assignments
					where
						(
							(assignments.submission=submissions.id)
							and (assignments.approved=true)
							and (
								assignments.scholar=(
									select
										auth.uid () as uid
								)
							)
						)
				)
			)
		)
	);

create policy "only token owners and venue admins can update a token" on "public"."tokens" as permissive
for update
	to authenticated using (
		(
			(
				(venue is not null)
				and public.isadmin (venue)
			)
			or (
				(scholar is not null)
				and (
					(
						select
							auth.uid () as uid
					)=scholar
				)
			)
		)
	)
with
	check (true);

create policy "stewards and admins can delete venues" on "public"."venues" as permissive for delete to authenticated,
anon using (
	(
		public.issteward ()
		or (
			(
				select
					auth.uid () as uid
			)=any (admins)
		)
	)
);

create policy "stewards and admins can update venues" on "public"."venues" as permissive
for update
	to authenticated,
	anon using (
		(
			public.issteward ()
			or (
				(
					select
						auth.uid () as uid
				)=any (admins)
			)
		)
	);

create policy "admins and volunteers can delete" on "public"."volunteers" as permissive for delete to authenticated,
anon using (
	(
		public.isadmin (
			(
				select
					roles.venueid
				from
					public.roles
				where
					(roles.id=volunteers.roleid)
			)
		)
		or (
			(
				select
					auth.uid () as uid
			)=scholarid
		)
	)
);

create policy "admins can invite and volunteers if not invite only" on "public"."volunteers" as permissive for insert to authenticated,
anon
with
	check (
		(
			public.isadmin (
				(
					select
						roles.venueid
					from
						public.roles
					where
						(roles.id=volunteers.roleid)
				)
			)
			or (
				(
					(
						select
							auth.uid () as uid
					)=scholarid
				)
				and (
					not (
						select
							roles.invited
						from
							public.roles
						where
							(roles.id=volunteers.roleid)
					)
				)
			)
		)
	);

create policy "only owners can transfer their tokens if approved" on "public"."transactions" as permissive for insert to authenticated,
anon
with
	check (
		(
			(status='proposed'::public.transaction_status)
			or (
				(status='approved'::public.transaction_status)
				and (
					(
						(from_scholar is not null)
						and (
							(
								select
									auth.uid () as uid
							)=from_scholar
						)
					)
					or (
						(from_venue is not null)
						and (
							(
								select
									auth.uid () as uid
							)=any (
								(
									select
										venues.admins
									from
										public.venues
									where
										(venues.id=transactions.from_venue)
								)::uuid[]
							)
						)
					)
				)
			)
		)
	);

create policy "only the giver and minters can update transactions" on "public"."transactions" as permissive
for update
	to authenticated,
	anon using (
		(
			(
				(
					select
						auth.uid () as uid
				)=from_scholar
			)
			or (
				(
					select
						auth.uid () as uid
				)=any (
					(
						select
							currencies.minters
						from
							public.currencies
						where
							(currencies.id=transactions.currency)
					)::uuid[]
				)
			)
			or (
				(from_venue is not null)
				and (
					(
						select
							auth.uid () as uid
					)=any (
						(
							select
								venues.admins
							from
								public.venues
							where
								(venues.id=transactions.from_venue)
						)::uuid[]
					)
				)
			)
		)
	);

create policy "transactions are only visible to minters and those involved" on "public"."transactions" as permissive for
select
	to authenticated,
	anon using (
		(
			(
				(
					select
						auth.uid () as uid
				)=from_scholar
			)
			or (
				(
					select
						auth.uid () as uid
				)=to_scholar
			)
			or (
				(
					select
						auth.uid () as uid
				)=any (
					(
						select
							currencies.minters
						from
							public.currencies
						where
							(currencies.id=transactions.currency)
					)::uuid[]
				)
			)
			or (
				(from_venue is not null)
				and (
					(
						select
							auth.uid () as uid
					)=any (
						(
							select
								venues.admins
							from
								public.venues
							where
								(venues.id=transactions.from_venue)
						)::uuid[]
					)
				)
			)
			or (
				(to_venue is not null)
				and (
					(
						select
							auth.uid () as uid
					)=any (
						(
							select
								venues.admins
							from
								public.venues
							where
								(venues.id=transactions.to_venue)
						)::uuid[]
					)
				)
			)
		)
	);

create trigger no_minter_admins BEFORE INSERT
or
update on public.venues for EACH row
execute FUNCTION public.no_minter_admins ();
