-- A per-submission switch that closes bidding while the submission is still under
-- review. An editor uses it when every seat has a reviewer but some of them have
-- not registered yet, so their assignments are still pending and the approved
-- count alone would leave bidding open.
alter table public.submissions
add column bidding_closed boolean not null default false;

-- Editable by clients alongside the other submission columns; the trigger below
-- narrows it to priority-0 assigned scholars.
revoke
update on public.submissions
from
	authenticated;

grant
update (
	venue,
	externalid,
	previousid,
	previous,
	submission_type,
	authors,
	payments,
	transactions,
	title,
	expertise,
	bidding_closed
) on public.submissions to authenticated;

-- Bidders see only submissions open for bidding, plus any they already hold an
-- assignment on.
drop policy "admins, authors, assigned, and bidders can view submissions" on "public"."submissions";

create policy "admins, authors, assigned, and bidders can view submissions" on "public"."submissions" as permissive for
select
	to anon,
	authenticated using (
		public.isadmin (venue)
		or (
			(
				select
					auth.uid ()
			)=any (authors)
		)
		or (
			-- An accepted volunteer on a biddable role, deciding what to bid on...
			exists (
				select
					volunteers.id
				from
					public.volunteers
				where
					volunteers.scholarid=(
						select
							auth.uid ()
					)
					and volunteers.accepted='accepted'::invited
					and volunteers.roleid=any (
						array(
							select
								roles.id
							from
								public.roles
							where
								roles.venueid=submissions.venue
								and roles.biddable=true
						)
					)
			)
			-- ...but only while the submission is open for bidding, unless the bidder
			-- already has an assignment on it (a pending bid, say), which should not
			-- point at a submission they can no longer open.
			and (
				not submissions.bidding_closed
				or exists (
					select
						assignments.id
					from
						public.assignments
					where
						assignments.submission=submissions.id
						and assignments.scholar=(
							select
								auth.uid ()
						)
				)
			)
		)
		or exists (
			select
				assignments.id
			from
				public.assignments
			where
				assignments.submission=submissions.id
				and assignments.approved=true
				and assignments.scholar=(
					select
						auth.uid ()
				)
		)
		-- The venue's editors, whether or not they are venue admins and whether or not
		-- they are assigned to this submission yet. Every other branch above requires a
		-- foothold ON the submission, so a priority-0 volunteer who was not also an admin
		-- could not see an unassigned submission at all -- which made a submission
		-- waiting for an editor invisible to precisely the people meant to pick it up.
		-- Deliberately the more generous of the two editor rules: isPriorityZero asks only
		-- that the role be accepted, while can_claim_editor_role also requires the
		-- volunteer to be active, because seeing a venue's work is not the same as taking
		-- a piece of it on.
		or public.isPriorityZero (submissions.venue)
	);

-- Bids may not be placed on a submission whose bidding is closed.
-- Whether the submission's editor has closed bidding on it.
--
-- The assignments INSERT policy needs this, and cannot read public.submissions itself:
-- the submissions SELECT policy reads public.assignments, so the policy would recurse.
-- SECURITY DEFINER, so it sees past both. It discloses one bit, about a submission whose
-- id the caller already holds.
create or replace function public.submission_bidding_closed (_submission uuid) returns boolean language sql security definer stable
set
	"search_path" to '' as $$
	select coalesce(
		(select s.bidding_closed from public.submissions s where s.id = _submission),
		false
	);
$$;

alter function public.submission_bidding_closed (uuid) OWNER to "postgres";

-- The INSERT policy is granted to authenticated only, so anon needs no EXECUTE.
revoke
execute on function public.submission_bidding_closed (uuid)
from
	public,
	anon;

grant
execute on function public.submission_bidding_closed (uuid) to authenticated;

drop policy "admins, approvers and volunteers can create assignments" on "public"."assignments";

create policy "admins, approvers and volunteers can create assignments" on "public"."assignments" for insert to "authenticated"
with
	check (
		(
			-- Whoever may approve an assignment for this role on this submission may
			-- create one. Covers venue admins and the submission's editor.
			--
			-- The old rule paired a venue-wide approver check with isAssigned, which
			-- asks only for an approved assignment in SOME role on the submission --
			-- so a scholar seated as a plain reviewer, who also volunteered in the
			-- approving role venue-wide, could seat further reviewers alongside
			-- themselves. The approver seated here may still seat anyone in the roles
			-- they approve, including themselves.
			public.can_approve_assignment (submission, role)
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
				-- The editor may close bidding on a submission that is still under review.
				and not public.submission_bidding_closed (submission)
			)
			-- An editor of the venue claiming a submission nobody is editing yet. See
			-- public.can_claim_editor_role above for why this branch has to exist and
			-- why it is drawn this narrowly; the checks here are the ones the function
			-- cannot make for itself, since it is not told who is being seated.
			or (
				scholar=(
					select
						auth.uid () as "uid"
				)
				and not bid
				and not completed
				and public.can_claim_editor_role (submission, role)
			)
		)
	);

-- Authors may update their own submission, but not close its bidding.
create or replace function public.enforce_submission_author_edits () RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
set
	"search_path" to '' as $$
begin
	if (
		new.authors is distinct from old.authors
		or new.payments is distinct from old.payments
		or new.transactions is distinct from old.transactions
		or new.bidding_closed is distinct from old.bidding_closed
	) and not exists (
		select 1
		from public.assignments a
		join public.roles r on r.id = a.role
		where a.submission = old.id
			and a.scholar = (select auth.uid())
			and a.approved = true
			and r.priority = 0
	) then
		raise exception 'Only priority-0 assigned scholars may change the author list or close bidding';
	end if;
	return new;
end;
$$;

alter function public.enforce_submission_author_edits () OWNER to "postgres";

-- Re-created, so re-revoked: see 20260831000000 and definer_grants.sql.
revoke
execute on function public.enforce_submission_author_edits ()
from
	public,
	anon,
	authenticated;

-- The weekly digest leaves out submissions whose bidding is closed.
create or replace function public.bidding_digest_candidates (
	_limit integer default 200,
	_cap integer default 7,
	_min_interval interval default '6 days'
) returns table (
	scholar uuid,
	fingerprint text,
	total integer,
	digest jsonb
) language sql stable security definer
set
	search_path='' as $$
	with recipients as materialized (
		select r.id, r.last, r.sent_at
		from private.bidding_digest_recipients (_min_interval) r
		order by r.sent_at nulls first, r.id
		limit _limit
	),
	open_seats as materialized (
		select
			r.id as role,
			r.name as role_name,
			r.priority as role_priority,
			coalesce(nullif(btrim(ve.short_title), ''), ve.title) as venue_name,
			coalesce(ve.slug, ve.id::text) as venue_path,
			sub.id as submission,
			sub.title,
			sub.expertise,
			sub.created_at,
			sub.authors,
			r.desired_assignments - (
				select count(*)
				from public.assignments a
				where a.submission = sub.id and a.role = r.id and a.approved
			) as missing
		from public.roles r
		join public.venues ve on ve.id = r.venueid and ve.inactive is null
		join public.submissions sub on sub.venue = ve.id and sub.status = 'reviewing'
			and not sub.bidding_closed
		where r.biddable
	),
	candidates as (
		select
			rc.id as scholar,
			o.*,
			coalesce(m.matches, '{}') as matches
		from recipients rc
		join public.volunteers v on v.scholarid = rc.id and v.active and v.accepted = 'accepted'
		join open_seats o on o.role = v.roleid
		left join lateral (
			-- The submission's keywords the volunteer claims for this role, once each, in the
			-- submission's spelling and order.
			select array_agg(k.label order by k.ord) as matches
			from (
				select distinct on (sk.key) sk.key, sk.label, sk.ord
				from private.expertise_keys (o.expertise) sk
				where sk.key in (select vk.key from private.expertise_keys (v.expertise) vk)
				order by sk.key, sk.ord
			) k
		) m on true
		where o.missing > 0
			and not coalesce(rc.id = any (o.authors), false)
			and not exists (
				select 1 from public.conflicts c where c.submissionid = o.submission and c.scholarid = rc.id
			)
			and not exists (
				select 1 from public.assignments a where a.submission = o.submission and a.scholar = rc.id
			)
	),
	ranked as (
		select
			c.*,
			row_number() over (
				partition by c.scholar, c.role
				order by c.missing desc, cardinality(c.matches) desc, c.created_at, c.submission
			) as place,
			count(*) over (partition by c.scholar, c.role) as in_group
		from candidates c
	),
	groups as (
		select
			scholar,
			jsonb_build_object(
				'venue', venue_name,
				'path', venue_path,
				'role', role_name,
				'items', jsonb_agg(
					jsonb_build_object('title', btrim(title), 'matches', to_jsonb(matches))
					order by place
				) filter (where place <= _cap),
				'more', greatest(max(in_group) - _cap, 0)
			) as grp,
			venue_name,
			role_priority
		from ranked
		group by scholar, role, venue_name, venue_path, role_name, role_priority
	),
	sets as (
		select
			scholar,
			count(*)::integer as total,
			encode(
				sha256(convert_to(string_agg(submission::text || ':' || role::text, E'\n' order by submission::text || ':' || role::text), 'UTF8')),
				'hex'
			) as fingerprint
		from candidates
		group by scholar
	)
	select
		rc.id,
		st.fingerprint,
		coalesce(st.total, 0),
		case
			when st.fingerprint is null or st.fingerprint = rc.last then null
			else (
				select jsonb_build_object('groups', jsonb_agg(g.grp order by g.venue_name, g.role_priority))
				from groups g
				where g.scholar = rc.id
			)
		end
	from recipients rc
	left join sets st on st.scholar = rc.id
	order by rc.sent_at nulls first, rc.id;
$$;

alter function public.bidding_digest_candidates (integer, integer, interval) OWNER to "postgres";

revoke
execute on function public.bidding_digest_candidates (integer, integer, interval)
from
	public,
	anon,
	authenticated;

grant
execute on function public.bidding_digest_candidates (integer, integer, interval) to service_role;
