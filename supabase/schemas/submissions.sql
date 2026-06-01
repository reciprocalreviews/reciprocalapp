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
	-- An optional free-text link to a previous external submission id, for a predecessor that is not (yet)
	-- on this platform. Retained for bulk import and the multi-year transition period.
	previousid text default null,
	-- An optional explicit foreign key to a previous submission on this platform (a resubmission chain).
	-- Null if there is no on-platform predecessor.
	previous uuid default null references submissions (id) on delete set null,
	-- The submission type of the paper
	submission_type uuid not null references submission_types (id),
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
	status submission_status not null default 'reviewing',
	-- When the submission was marked done (null while still under review).
	-- Set by the mark_submission_done RPC; cannot be reverted.
	completed_at timestamp with time zone default null
);

alter table public.submissions OWNER to "postgres";

grant all on table public.submissions to "anon";

grant all on table public.submissions to "authenticated";

grant all on table public.submissions to "service_role";

-- Lock the completion state (status, completed_at) from direct UPDATEs: only the
-- mark_submission_done RPC (SECURITY DEFINER) may write them. A column-level
-- revoke is ineffective while authenticated holds the TABLE-level UPDATE granted
-- by `grant all` above, so remove the table-level UPDATE and re-grant only the
-- editable columns. (The author list among these is further gated to priority-0
-- assigned scholars by the enforce_submission_author_edits trigger.)
revoke update on public.submissions from authenticated;

grant update (
	venue, externalid, previousid, previous, submission_type, authors, payments, transactions, title, expertise
) on public.submissions to authenticated;

--------------------------------------
-- Indexes
create index submissions_externalid_index on public.submissions using btree (externalid);

create index submissions_previous_index on public.submissions using btree (previous);

create index submissions_scholar_index on public.submissions using btree (authors);

create index submissions_venue_index on public.submissions using btree (venue);

--------------------------------------
-- Security
alter table public.submissions ENABLE row LEVEL SECURITY;

-- Select policy is in assignments.sql, after assignments table is declared.
create policy "anyone can create submissions" on public.submissions for INSERT to authenticated
with
	check (true);

create policy "admins can delete submissions" on public.submissions for DELETE to authenticated using (public.isAdmin (venue));

alter publication supabase_realtime
add table submissions;
