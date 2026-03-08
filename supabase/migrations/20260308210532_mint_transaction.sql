drop policy "only owners can transfer their tokens if approved" on "public"."transactions";

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
					or (
						(from_scholar is null)
						and (from_venue is null)
					)
				)
			)
		)
	);

alter table "public"."transactions"
drop constraint "check_from";

alter table "public"."transactions"
add constraint "check_from" check ((num_nonnulls (from_scholar, from_venue)<=1)) not valid;

alter table "public"."transactions" validate constraint "check_from";
