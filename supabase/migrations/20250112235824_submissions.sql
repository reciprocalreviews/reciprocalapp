-- The status of a submission, in relation to payments.
create type submission_status as enum ('reviewing', 'done');

-- Individual submissions under review
create table submissions (
  -- The unique ID of the submission
  id uuid not null default uuid_generate_v1() primary key,
  -- The venue to which the submission corresponds
  venue uuid not null references venues(id),
  -- The external unique identifier of the submission, such as a submission number or manuscript number
  externalid text not null,
  -- An optional link to a previous external submission id
  previousid text default null,
  -- The scholars associated with the submission
  authors uuid[] not null check (cardinality(authors) > 0),
  -- The token amounts proposed for the submission, corresponding to the authors
  payments integer[] not null check (cardinality(payments) = cardinality(authors)),
  -- The transactions corresponding to the payments, corresponding to the authors. Null uuid of not yet paid.
  transactions uuid[] not null check (cardinality(transactions) = cardinality(authors)),
  -- An optional title for public bidding
  title text not null default ''::text,
  -- An optional description of expertise required for public bidding
  expertise text default null,
  -- The status of the submission in relation to payments.
  status submission_status not null default 'reviewing'
);

-- Make it fast to retrieve the submissions of a scholar or venue.
create index submissions_scholar_index on submissions(authors);
create index submissions_venue_index on submissions(venue);
create index submissions_externalid_index on submissions(externalid);

-- Individuals who could be assigned to review a particular paper
create table assignments (
  -- The unique ID of the bid
  id uuid not null default uuid_generate_v1() primary key,
  -- The venue to which this assignment corresponds
  venue uuid not null references venues(id),
  -- The submission bid on
  submission uuid not null references submissions(id),
  -- The scholar who bid
  scholar uuid not null references scholars(id),
  -- The role for which the bid occurred
  role uuid not null references roles(id),
  -- True if a bid by the reviewer.
  bid boolean not null default false,
  -- True if the assignment has been approved
  approved boolean not null default false,
);

-- Make it fast to retrieve the assignments of a scholar or submission.
create index assignments_scholar_index on assignments(scholar);
create index assignments_submission_index on assignments(submission);

-- Enable RLS for submissions
alter table public.submissions
  enable row level security;

create policy "editors can create submissions" on public.submissions
  for insert to anon, authenticated with check (isEditor(venue));

-- If someone is an author, editor, or the scholar has a role in the venue that is biddable,
-- then they can see the submission.
create policy "authors, editors, and bidders can view submissions" on public.submissions
  for select to anon, authenticated using (
    (auth.uid() = any(authors)) or
    (isEditor(venue)) or
    (exists 
      -- Find all of the accepted volunteering by this scholar for a role that is biddable
      (select id from volunteers where 
        scholarid = auth.uid() and 
        accepted = 'accepted' and 
        roleid = any(array(select id from roles where venue = venue and invited = false))
      )
    )
  );

create policy "editors can update submissions" on public.submissions
  for update to anon, authenticated 
    using (isEditor(venue))
    with check (true);

create policy "editors can delete submissions" on public.submissions
  for delete to anon, authenticated 
  using (isEditor(venue));


-- Enable RLS for assignments
alter table public.assignments
  enable row level security;

-- Editors or scholars who are active volunteers for the inserted role can create bidding assignments
create policy "editors can create assignments" on public.assignments
  for insert to anon, authenticated with check (
    isEditor(venue) or 
    (
      bid and 
      exists (
        select from volunteers where 
          volunteers.roleid = role and 
          volunteers.scholarid = auth.uid() and 
          volunteers.active and 
          volunteers.accepted="accepted"
      )
    )
  );

create policy "editors can see assignments" on public.assignments
  for select to anon, authenticated using (isEditor(venue) or scholar = auth.uid());

create policy "editors can update assignments" on public.assignments
  for update to anon, authenticated 
    using (isEditor(venue) or scholar = auth.uid())
    with check (true);

create policy "editors can delete assignments" on public.assignments
  for delete to anon, authenticated 
  using (isEditor(venue) or scholar = auth.uid());
