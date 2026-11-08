-- Per-role volunteer visibility.
--
-- Paired with supabase/schemas/roles.sql (the enum and the column) and
-- supabase/schemas/volunteers.sql (both functions and the SELECT policy). Must run
-- AFTER 20260914000000_call_for_bids.sql, which is the newest migration at the time
-- of writing; nothing here depends on it, but the ordering keeps the replay honest.
--
-- WHY
--
-- A venue's volunteer roster is published at /venue/<venue>/volunteers to anyone at
-- all, signed in or not, because public.volunteers' SELECT policy was `using (true)`
-- for both authenticated and anon. That listing is a credential, and it was being
-- handed out for the act of signing up: people accumulate volunteer roles across
-- venues, contribute nothing, and collect a public record of it. A venue's only
-- recourse was to make the role invite-only, which is a different decision with
-- different consequences.
--
-- roles.volunteer_visibility lets a venue say who the roster is for: everyone
-- ('all', the default and today's behaviour), only the people who have completed
-- work at the venue ('completed'), or nobody outside the people who staff the role
-- ('none').
--
-- WHAT DOES NOT CHANGE
--
-- Every existing role backfills to 'all', so no venue's page changes until an admin
-- opts in. Counts stay public regardless -- public.venue_volunteer_counts below --
-- because hiding the number takes a venue's recruiting signal away along with the
-- names, which is not what hiding a roster is for.
--
-- TWO EXEMPTIONS, both of them status a person cannot award themselves:
--
--  * Invite-only roles. The invitation IS the vetting.
--  * The venue's priority-0 editor role. Its holders are the venue's public face,
--    and -- less obviously -- SupabaseCRUD.emailEditorsOf resolves the editor
--    mailing list by reading public.volunteers with the CALLER's own session,
--    discarding the error and treating an empty read as "nobody to mail". Its
--    callers include authors (SubmissionNeedsEditor), bidders (NewBid), reviewers
--    (ConflictDeclared) and volunteers changing their own status. Without this
--    exemption an admin who opened the Editor role to self-volunteering and then
--    restricted it would silently stop notifying every editor who is not also a
--    venue admin. Worth revisiting by moving that fan-out server-side, the way
--    queue_call_for_bids already resolves its recipients.
--
-- ONE NARROWING WORTH NAMING
--
-- The conflicts INSERT policy (supabase/schemas/conflicts.sql) has a branch that
-- reads public.volunteers filtered on conflicts.scholarid rather than auth.uid() --
-- the only inline read of this table in another table's policy that is not
-- self-scoped. An inline read in a policy is gated by THAT table's policy, so the
-- branch narrows here. Both real paths survive: venue admins short-circuit on the
-- isAdmin branch ahead of it, and a scholar declaring their own conflict reads their
-- own row. What narrows is a non-admin declaring a conflict on somebody else at a
-- restricted role -- a path the policy never should have allowed, since it does not
-- check that the caller is the scholar. conflicts_rls.sql pins the surviving cases.
--
-- The revoke travels WITH each create or replace, in this same migration: Supabase's
-- default privileges re-grant EXECUTE to anon on every function creation, so a
-- revoke left in an earlier migration is undone by this one. Both functions are then
-- granted to anon DELIBERATELY -- a policy expression is evaluated as the QUERYING
-- role, and this policy is granted to anon, so anon must hold EXECUTE on the
-- predicate or the policy errors for signed-out visitors. definer_grants.sql
-- allowlists both.

--------------------------------------
-- 1. The setting.
create type public.volunteer_visibility as enum('all', 'completed', 'none');

alter type public.volunteer_visibility OWNER to postgres;

-- NOT NULL with a default, so every existing role backfills to today's behaviour in
-- one pass and public.create_role needs no change -- it names its columns.
alter table public.roles
add column if not exists volunteer_visibility public.volunteer_visibility default 'all'::public.volunteer_visibility not null;

--------------------------------------
-- 2. The predicate, and the counts that have to survive it.
-- The single definition of "may this viewer see this volunteer record". Mirrors
-- nothing in TypeScript: the roster is read straight from the table, so this
-- policy is the only place the rule lives.
--
-- Keyed on the ROW ID rather than on (roleid, scholarid), which is the signature
-- it looks like it wants. This function is granted to anon and public.scholars is
-- world-readable, so a (roleid, scholarid) form would answer, for any scholar id
-- an anonymous caller cared to try, whether that scholar has completed an
-- assignment at the venue -- whether or not they volunteer for the role at all.
-- That is the disclosure public.token_events and public.tokens_as_of already
-- refuse on the grounds that it leaks reviewing activity venue anonymity is meant
-- to protect. Taking the row id confines the answer to a row whose id the caller
-- already holds, and holding it they could have selected the row instead.
--
-- SECURITY DEFINER is load-bearing: the branches below read public.volunteers and
-- public.assignments, and the same tests written inline in the policy would be
-- gated by those tables' own policies -- public.volunteers by this very one. The
-- table is owned by postgres and does not FORCE row level security, so the reads
-- bypass RLS and cannot recurse. Same reason public.can_claim_editor_role and
-- public.isAuthor are DEFINER.
--
-- STABLE because a policy predicate must be; see ARCHITECTURE.md on the
-- 20260830020000 sweep. It buys less here than usual -- the planner will not
-- inline a function that is both SECURITY DEFINER and carries a SET clause, and
-- _volunteer varies per row -- which is why the policy below tests the three cheap
-- cases inline and reaches this function only for a restricted role.
--
-- plpgsql rather than sql, for the same reason public.isConflicted is: a sql body
-- is parsed and resolved when the function is created, and this one reads
-- public.assignments, whose schema file loads AFTER this one. A sql body would
-- create fine during a migration replay and fail when the declarative schema is
-- rebuilt in dependency order.
create or replace function public.can_see_volunteer (_volunteer uuid) returns boolean language plpgsql security definer stable
set
	"search_path" to '' as $$
begin
	return exists (
		select 1
		from public.volunteers v
		join public.roles r on r.id = v.roleid
		where v.id = _volunteer
			and (
				-- Your own record. Load-bearing well beyond courtesy: the submissions
				-- SELECT policy and the assignments INSERT policy each read
				-- public.volunteers inline, so both are gated by this policy. Each
				-- filters to auth.uid(), so this branch is what keeps bidding and
				-- editor-claiming working at a role that publishes nobody.
				v.scholarid = (select auth.uid())
				-- An invitation is vetting nobody can award themselves, so holding an
				-- invite-only role is earned status and the setting does not apply.
				or r.invited
				-- The venue's editors are its public face rather than its grift
				-- surface. Also load-bearing: emailEditorsOf resolves the editor
				-- mailing list by reading this table with the CALLER's session, and
				-- its callers include authors, bidders and reviewers.
				or r.priority = 0
				-- The default, and true of every role until an admin opts out. Tested
				-- before the subquery branches below so the common case never runs one.
				or r.volunteer_visibility = 'all'
				-- Whoever staffs the role sees who is available to staff it: the venue's
				-- admins, its editors, and the holders of the role that approves this
				-- one. That last branch is venue-wide, which ARCHITECTURE.md records as
				-- the rule 20260913000000 deliberately removed -- from deciding who may
				-- ACT on a submission. This is a read of the roster and grants no
				-- authority; an approver who cannot see the pool cannot seat anyone from
				-- it.
				or public.isAdmin (r.venueid)
				or public.isPriorityZero (r.venueid)
				or (
					r.approver is not null
					and exists (
						select 1
						from public.volunteers av
						where av.roleid = r.approver
							and av.scholarid = (select auth.uid())
							and av.accepted = 'accepted'
					)
				)
				-- Otherwise the role's own setting decides. 'completed' means completed
				-- anywhere at this venue, not only in this role: contributing to the
				-- venue is what the listing is meant to recognize.
				--
				-- Joined through public.roles rather than read from assignments.venue.
				-- Both columns carry a foreign key, but assignments.venue is a
				-- denormalized copy the client supplies (createAssignment writes it
				-- directly) and nothing constrains it to agree with the venue of
				-- assignments.role -- no check, no trigger, and the INSERT policy never
				-- compares them. roles.venueid is the authoritative answer, and every
				-- other authorization rule in the schema reaches the venue the same way.
				or (
					r.volunteer_visibility = 'completed'
					and exists (
						select 1
						from public.assignments a
						join public.roles ar on ar.id = a.role
						where a.scholar = v.scholarid
							and ar.venueid = r.venueid
							and a.completed
					)
				)
			)
	);
end;
$$;

alter function public.can_see_volunteer (_volunteer uuid) OWNER to postgres;

revoke
execute on function public.can_see_volunteer (_volunteer uuid)
from
	public;

grant
execute on function public.can_see_volunteer (_volunteer uuid) to anon;

grant
execute on function public.can_see_volunteer (_volunteer uuid) to authenticated;

-- Per-role volunteer counts, regardless of who may see the volunteers themselves.
--
-- The policy above withholds rows the interface still has to count: the role card
-- badge, the "N volunteers" line, the venue's dashboard tile and the roster page's
-- section headings. A count derived from the filtered rows would quietly mean
-- something different to every reader, and would take a venue's recruiting signal
-- away along with the names -- which is not what hiding a roster is for. So this
-- answers the count and nothing else, the way public.submission_has_editor answers
-- one bit and public.currency_holder_counts answers an aggregate.
--
-- Safe to leave open to anon for the same reason currency_holder_counts is: it
-- discloses no name and no membership, only a number that is public today.
--
-- Counts EVERY row for the role, including inactive rows and declined invitations,
-- because that is what the interface counts today. Narrowing it would change every
-- number on the page for every viewer, which is a separate decision.
create or replace function public.venue_volunteer_counts (_venue uuid) returns table (role uuid, volunteer_count integer) language sql security definer stable
set
	"search_path" to '' as $$
	select r.id, count(v.id)::integer
	from public.roles r
	left join public.volunteers v on v.roleid = r.id
	where r.venueid = _venue
	group by r.id;
$$;

alter function public.venue_volunteer_counts (_venue uuid) OWNER to postgres;

revoke
execute on function public.venue_volunteer_counts (_venue uuid)
from
	public;

grant
execute on function public.venue_volunteer_counts (_venue uuid) to anon;

grant
execute on function public.venue_volunteer_counts (_venue uuid) to authenticated;

--------------------------------------
-- 3. The policy. Dropped and recreated in the SAME migration: a migration that
-- drops a SELECT policy and creates its replacement later leaves a window in which
-- an RLS-enabled table has no SELECT policy at all, which denies everything.
drop policy "anyone can view volunteers" on public.volunteers;

-- Renamed rather than replaced in place: "anyone can view volunteers" was the
-- rule as well as the name, and leaving the name on a policy that no longer says
-- so would make the one place this schema states its rules in prose into the one
-- place it misstates them.
--
-- The three cheap tests are inline rather than left to can_see_volunteer, which
-- carries them too. public.roles is world-readable, so reading invited, priority
-- and the setting here discloses nothing and creates no oracle -- and it means a
-- venue that has not opted in pays one primary-key lookup per row instead of a
-- function call the planner cannot inline. The function remains the complete
-- rule; this is a fast path in front of it, not a substitute for it.
create policy "volunteer visibility follows the role's setting" on public.volunteers for
select
	to authenticated,
	anon using (
		(
			scholarid=(
				select
					auth.uid ()
			)
		)
		or exists (
			select
				1
			from
				public.roles r
			where
				r.id=volunteers.roleid
				and (
					r.invited
					or r.priority=0
					or r.volunteer_visibility='all'
				)
		)
		or public.can_see_volunteer (id)
	);
