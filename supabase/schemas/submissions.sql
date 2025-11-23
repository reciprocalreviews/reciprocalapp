/* SCHEMA  */
-- The status of a submission, in relation to payments.
create type "public"."submission_status" as enum('reviewing', 'done');

alter type "public"."submission_status" OWNER to "postgres";

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

-- Individual submissions under review
create table if not exists "public"."submissions" (
	-- The unique ID of the submission
	"id" "uuid" default "gen_random_uuid" () not null,
	-- The venue to which the submission corresponds
	"venue" "uuid" not null,
	-- The external unique identifier of the submission, such as a submission number or manuscript number
	"externalid" "text" not null,
	-- An optional link to a previous external submission id
	"previousid" "text",
	-- The scholars associated with the submission
	"authors" "uuid" [] not null,
	-- The token amounts proposed for the submission, corresponding to the authors
	"payments" integer[] not null,
	-- The transactions corresponding to the payments, corresponding to the authors. Null uuid of not yet paid.
	"transactions" "uuid" [] not null,
	-- An optional title for public bidding
	"title" "text" default ''::"text" not null,
	-- An optional description of expertise required for public bidding
	"expertise" "text",
	-- The status of the submission in relation to payments.
	"status" "public"."submission_status" default 'reviewing'::"public"."submission_status" not null,
	-- Must be at least one author
	constraint "submissions_authors_check" check (("cardinality" ("authors")>0)),
	-- Payments and transactions length must match
	constraint "submissions_check" check (
		(
			"cardinality" ("payments")="cardinality" ("authors")
		)
	),
	-- Transactions length must match authors length
	constraint "submissions_check1" check (
		(
			"cardinality" ("transactions")="cardinality" ("authors")
		)
	)
);

alter table "public"."submissions" OWNER to "postgres";

grant all on table "public"."submissions" to "anon";

grant all on table "public"."submissions" to "authenticated";

grant all on table "public"."submissions" to "service_role";

alter table only "public"."submissions"
add constraint "submissions_pkey" primary key ("id");

alter table only "public"."submissions"
add constraint "submissions_venue_fkey" foreign KEY ("venue") references "public"."venues" ("id");

--------------------------------------
-- Indexes
create index "submissions_externalid_index" on "public"."submissions" using "btree" ("externalid");

create index "submissions_scholar_index" on "public"."submissions" using "btree" ("authors");

create index "submissions_venue_index" on "public"."submissions" using "btree" ("venue");

--------------------------------------
-- Security
alter table "public"."submissions" ENABLE row LEVEL SECURITY;

create policy "authors, editors, and bidders can view submissions" on "public"."submissions" for
select
	to "authenticated",
	"anon" using (
		(
			(
				(
					select
						"auth"."uid" () as "uid"
				)=any ("authors")
			)
			or "public"."iseditor" ("venue")
			or (
				exists (
					select
						"volunteers"."id"
					from
						"public"."volunteers"
					where
						(
							(
								"volunteers"."scholarid"=(
									select
										"auth"."uid" () as "uid"
								)
							)
							and (
								"volunteers"."accepted"='accepted'::"public"."invited"
							)
							and (
								"volunteers"."roleid"=any (
									array(
										select
											"roles"."id"
										from
											"public"."roles"
										where
											("submissions"."venue"="submissions"."venue")
									)
								)
							)
						)
				)
			)
		)
	);

create policy "editors can create submissions" on "public"."submissions" for INSERT to "authenticated"
with
	check ("public"."iseditor" ("venue"));

create policy "editors can update submissions" on "public"."submissions"
for update
	to "authenticated" using ("public"."iseditor" ("venue"))
with
	check (true);

create policy "editors can delete submissions" on "public"."submissions" for DELETE to "authenticated" using ("public"."iseditor" ("venue"));
