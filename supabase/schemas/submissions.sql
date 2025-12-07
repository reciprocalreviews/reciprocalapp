/* SCHEMA  */
-- The status of a submission, in relation to payments.
create type public.submission_status as enum('reviewing', 'done');

alter type public.submission_status OWNER to "postgres";

create table submissions (
	-- The unique ID of the submission
	id uuid not null default gen_random_uuid() primary key,
	-- The venue to which the submission corresponds
	venue uuid not null references venues (id),
	-- The external unique identifier of the submission, such as a submission number or manuscript number
	externalid text not null,
	-- An optional link to a previous external submission id
	previousid text default null,
	-- The scholars associated with the submission
	authors uuid[] not null check (cardinality(authors)>0),
	-- The token amounts proposed for the submission, corresponding to the authors
	payments integer[] not null check (cardinality(payments)=cardinality(authors)),
	-- The transactions corresponding to the payments, corresponding to the authors. Null uuid of not yet paid.
	transactions uuid[] not null check (cardinality(transactions)=cardinality(authors)),
	-- An optional title for public bidding
	title text not null default ''::text,
	-- An optional description of expertise required for public bidding
	expertise text default null,
	-- The status of the submission in relation to payments.
	status submission_status not null default 'reviewing'
);

alter table public.submissions OWNER to "postgres";

grant all on table public.submissions to "anon";

grant all on table public.submissions to "authenticated";

grant all on table public.submissions to "service_role";

--------------------------------------
-- Indexes
create index submissions_externalid_index on public.submissions using btree (externalid);

create index submissions_scholar_index on public.submissions using btree (authors);

create index submissions_venue_index on public.submissions using btree (venue);

--------------------------------------
-- Security
alter table public.submissions ENABLE row LEVEL SECURITY;

create policy "authors, editors, and bidders can view submissions" on public.submissions for
select
	to "authenticated",
	"anon" using (
		(
			(
				(
					select
						auth.uid () as uid
				)=any (authors)
			)
			or public.isEditor (venue)
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
											(roles.venueid=submissions.venue)
									)
								)
							)
						)
				)
			)
		)
	);

create policy "anyone can create submissions" on public.submissions for INSERT to authenticated
with
	check (true);

create policy "editors can update submissions" on public.submissions
for update
	to authenticated using (public.isEditor (venue))
with
	check (true);

create policy "editors can delete submissions" on public.submissions for DELETE to authenticated using (public.isEditor (venue));
