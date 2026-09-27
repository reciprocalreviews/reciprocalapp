--------------------------------------
-- The weekly "open for bidding" digest
--
-- Bidding only works if volunteers come and look, and nothing told them to: a volunteer who
-- forgot, or never knew new submissions had arrived, simply never bid. So every Monday the
-- `bidding-digest-weekly` cron asks the `remind` function to email each available volunteer
-- the submissions still open for bidding in the roles they volunteer for (see the
-- BiddingDigest template in supabase/functions/_shared/templates.ts).
--
-- Who is told about what, and in what order, is decided here, in SQL, where authorship,
-- conflicts, assignments and rankings can be worked out as sets for every volunteer at once.
-- The `remind` function formats and queues what bidding_digest_candidates returns, and the
-- BiddingDigest template renders it at send time.
--------------------------------------
-- Schema
--
-- One row per scholar: when they were last sent a digest and which list it was, and when they
-- were last looked at and found to have nothing new.
--
-- `fingerprint` is a SHA-256 of the sorted (submission, role) pairs the digest covered, before
-- the cap. It exists so an unchanged list is not sent again: "only when the list has changed"
-- is a promise the email makes. It is a hash rather than the pairs because the pairs are not
-- needed back, only compared.
--
-- `checked_at` records a scholar the Monday job reached and had nothing to send -- no open
-- submissions, or the same list as last time -- so the job's later runs that day move on to
-- the people still waiting rather than re-ranking the same lists every five minutes. A row can
-- therefore exist with no digest ever sent, which is why `sent_at` and `fingerprint` are
-- nullable, and null together.
--
-- Not columns on public.scholars, which is world-readable: when a scholar was last emailed is
-- nobody else's business.
create table if not exists public.bidding_digests (
	scholar uuid not null,
	sent_at timestamp with time zone,
	fingerprint text constraint bidding_digests_fingerprint_check check (fingerprint~'^[0-9a-f]{64}$'),
	checked_at timestamp with time zone,
	constraint bidding_digests_sent_check check ((sent_at is null)=(fingerprint is null))
);

alter table public.bidding_digests OWNER to "postgres";

alter table only public.bidding_digests
add constraint "bidding_digests_pkey" primary key ("scholar");

-- Left in place by erasure, which anonymises the scholar row rather than deleting it: the row
-- holds an id, a time and a hash of submission ids, which says no more than the BiddingDigest
-- row erasure already keeps in public.emails (its event and time). Erasure also sets
-- `available` false, so no further digest is sent.
alter table only public.bidding_digests
add constraint "bidding_digests_scholar_fkey" foreign KEY ("scholar") references public.scholars ("id") on delete cascade;

--------------------------------------
-- SECURITY
-- Service role only. RLS with no policies, and the table privileges revoked outright as
-- well, so nothing signed in can read when anyone was last emailed.
alter table public.bidding_digests ENABLE row LEVEL SECURITY;

revoke all on table public.bidding_digests
from
	anon,
	authenticated;

grant all on table public.bidding_digests to "service_role";

--------------------------------------
-- FUNCTIONS
--
-- private.expertise_keys: one expertise field as keywords -- split on commas, trimmed, empties
-- dropped -- each with its position, the spelling as written, and the case-folded key it is
-- matched on. The SQL twin of expertiseTags in supabase/functions/_shared/expertise.ts,
-- which the volunteers roster uses for its chips, so a keyword the email says matched is a
-- chip on that page; supabase/tests/rpc/bidding_digest.sql holds the two to the same cases.
-- In `private`, which the API does not expose: it is a helper, not an endpoint.
create or replace function private.expertise_keys (_expertise text) returns table (ord bigint, label text, key text) language sql immutable
set
	search_path='' as $$
	select t.ord, t.label, lower(t.label)
	from (
		select u.ord, regexp_replace(u.raw, '^[[:space:]]+|[[:space:]]+$', '', 'g') as label
		from unnest(string_to_array(coalesce(_expertise, ''), ',')) with ordinality as u (raw, ord)
	) t
	where t.label <> '';
$$;

alter function private.expertise_keys (text) OWNER to "postgres";

-- private.bidding_digest_recipients: the scholars due a look this week -- available, with a
-- verified address, volunteering for at least one biddable role, not silenced, and neither sent
-- a digest nor found to have nothing new within _min_interval. Shared by
-- bidding_digest_candidates, which works through them, and report_bidding_digest_backlog, which
-- counts whoever is left, so the two cannot disagree about who was owed one.
create or replace function private.bidding_digest_recipients (_min_interval interval) returns table (
	id uuid,
	last text,
	sent_at timestamp with time zone
) language sql stable
set
	search_path='' as $$
	select s.id, d.fingerprint, d.sent_at
	from public.scholars s
	left join public.bidding_digests d on d.scholar = s.id
	where s.available
		and s.email is not null
		and coalesce(greatest(d.sent_at, d.checked_at), '-infinity') <= now() - _min_interval
		and exists (
			select 1
			from public.volunteers v
			join public.roles r on r.id = v.roleid and r.biddable
			where v.scholarid = s.id and v.active and v.accepted = 'accepted'
		)
		and public.notification_allowed(s.id, 'BiddingDigest');
$$;

alter function private.bidding_digest_recipients (interval) OWNER to "postgres";

-- bidding_digest_candidates: each scholar's digest, ready to send, a page of scholars at a time.
--
-- Everything the email needs is decided here, where it can be done as sets: who may be told
-- about what, how each list is ranked, which items make the cap, how many are left over, and
-- the fingerprint that says whether the list changed. The `remind` function only formats and
-- queues what this returns. It used to receive every candidate and rank them itself, which at
-- 2,000 volunteers across 20 venues of 100 open submissions was ~27 MB a page of 200 scholars
-- -- past what an edge function's 2 s of CPU and 256 MB can parse, let alone rank.
--
-- A candidate needs all of:
--   - the volunteer is active and has accepted the role, and the role is biddable;
--   - the venue is not switched off, and the submission is still under review;
--   - the role still wants people: fewer approved assignments than desired_assignments.
--     Pending bids do not count, as on the submissions page;
--   - the scholar says they are available, has a verified address, and has not silenced
--     BiddingDigest;
--   - the scholar is not an author, has not declared a conflict, and has no assignment of any
--     kind on the submission -- a bid already placed, or a seat in another role. Someone
--     already editing a paper should not be invited to review it;
--   - the scholar was not sent a digest, or found to have nothing new, within _min_interval.
--     The weekly cadence is the cron's schedule; this stops Monday's later runs repeating
--     anyone an earlier run reached.
--
-- Within each (venue, role) the list is ordered by how many people the submission is missing,
-- then by how many of its expertise keywords the volunteer claims for that role, then oldest
-- first; the first _cap are listed and the rest counted. Groups are ordered by venue name, then
-- role priority. venue_name is the short title the venue bar shows, falling back to the title.
--
-- `fingerprint` is a SHA-256 of the scholar's full set of (submission, role) pairs, before the
-- cap -- deliberately not the order or the missing counts, since a list whose only change is
-- that a paper gained a reviewer is the same list. `digest` is null when there is nothing to
-- send: no candidates, or the same list as last time.
--
-- A page is the _limit scholars who have waited longest -- never sent one first, then the
-- longest since their last -- and every one of them gets a row, so a short page means the end.
-- There is no offset or cursor: the caller stamps everyone it reaches (queue_bidding_digest
-- for a sent digest, mark_bidding_digests_checked for nothing to send), which drops them out of
-- the set, so the next call returns the next people waiting. Longest-waiting first is what
-- makes a Monday too big to finish fair: whoever it did not reach is first in line next week,
-- rather than the same scholars missing out every week.
--
-- SECURITY DEFINER over authorship and conflicts, which are private, so it is the service
-- role's alone.
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

-- Explicitly revoked, not merely un-granted: Supabase's default privileges hand anon and
-- authenticated EXECUTE on every function created in `public`. See 20260831000000 and
-- supabase/tests/rls/definer_grants.sql check 5.
revoke
execute on function public.bidding_digest_candidates (integer, integer, interval)
from
	public,
	anon,
	authenticated;

grant
execute on function public.bidding_digest_candidates (integer, integer, interval) to service_role;

-- queue_bidding_digest: send one scholar their digest, unless it would repeat the last one.
--
-- Takes the rendered arguments and the fingerprint from the `remind` function, which built
-- them from bidding_digest_candidates. Like queue_reminder_email it accepts no address, no
-- subject and no body: the recipient is resolved from the scholar id and re-checked for an
-- address, availability and the preference, and the body is rendered from the template at
-- send time.
--
-- The check and the stamp happen in one transaction under a per-scholar lock, so two
-- overlapping runs cannot both decide the list is new. Only a digest that was actually queued
-- is stamped: a scholar who had nothing to receive it at has not been sent this list.
--
-- Returns the number of emails queued, 0 or 1.
create or replace function public.queue_bidding_digest (
	_scholar uuid,
	_args text[],
	_fingerprint text,
	_min_interval interval default '6 days'
) returns integer language plpgsql security definer
set
	search_path='' as $$
declare
	_last public.bidding_digests;
	_count integer;
begin
	if _fingerprint is null or _fingerprint !~ '^[0-9a-f]{64}$' then
		raise exception 'A SHA-256 fingerprint is required';
	end if;

	perform pg_advisory_xact_lock(hashtextextended('bidding_digest:' || _scholar::text, 0));

	select * into _last from public.bidding_digests where scholar = _scholar;
	if found and (_last.sent_at > now() - _min_interval or _last.fingerprint = _fingerprint) then
		return 0;
	end if;

	insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
	select 'BiddingDigest', s.id, null, null, s.email, null, null, to_jsonb(_args)
	from public.scholars s
	where s.id = _scholar
		and s.email is not null
		and s.available
		and public.notification_allowed(s.id, 'BiddingDigest');
	get diagnostics _count = row_count;

	if _count > 0 then
		insert into public.bidding_digests (scholar, sent_at, fingerprint)
		values (_scholar, now(), _fingerprint)
		on conflict (scholar) do update
		set sent_at = excluded.sent_at, fingerprint = excluded.fingerprint;
	end if;

	return _count;
end;
$$;

alter function public.queue_bidding_digest (uuid, text[], text, interval) OWNER to "postgres";

-- Service role only, for the same reason as queue_reminder_email: open, it would let anyone
-- signed in mail any scholar a list of their choosing.
revoke
execute on function public.queue_bidding_digest (uuid, text[], text, interval)
from
	public,
	anon,
	authenticated;

grant
execute on function public.queue_bidding_digest (uuid, text[], text, interval) to service_role;

-- mark_bidding_digests_checked: record that the Monday job reached these scholars and had
-- nothing to send them, so its later runs that day move on. One call per page rather than one
-- per scholar. Returns how many rows were stamped.
create or replace function public.mark_bidding_digests_checked (_scholars uuid[]) returns integer language plpgsql security definer
set
	search_path='' as $$
declare
	_count integer;
begin
	insert into public.bidding_digests (scholar, checked_at)
	select distinct u.id, now()
	from unnest(_scholars) as u (id)
	join public.scholars s on s.id = u.id
	on conflict (scholar) do update
	set checked_at = excluded.checked_at;
	get diagnostics _count = row_count;
	return _count;
end;
$$;

alter function public.mark_bidding_digests_checked (uuid[]) OWNER to "postgres";

revoke
execute on function public.mark_bidding_digests_checked (uuid[])
from
	public,
	anon,
	authenticated;

grant
execute on function public.mark_bidding_digests_checked (uuid[]) to service_role;

-- report_bidding_digest_backlog: after Monday's last run, tell the stewards if anyone due a
-- digest was not reached.
--
-- The Monday job paces itself under Resend's rate limit and runs every five minutes from 12:00
-- to 15:55 UTC. Past what that window can send, the rest simply hear nothing this week, and a
-- job whose only output is an HTTP response to pg_cron would never say so. Run by its own
-- cron at 16:00 UTC, in the database, so it reports even when the edge function did not run at
-- all. Longest-waiting-first ordering means whoever is counted here goes first next week.
--
-- Inserted directly into the steward inbox, as reconcile_ledger does: there is no caller to
-- resolve, and the alias always resolves. Returns the count, 0 when everyone was reached.
create or replace function public.report_bidding_digest_backlog (_min_interval interval default '6 days') returns integer language plpgsql security definer
set
	search_path='' as $$
declare
	_left integer;
begin
	select count(*) into _left from private.bidding_digest_recipients (_min_interval);
	if _left > 0 then
		raise warning 'bidding digest: % volunteer(s) due a digest were not reached', _left;
		insert into public.emails (event, email, scholar, args)
		values (
			'BiddingDigestBacklog',
			public.steward_inbox(),
			null,
			jsonb_build_array(to_char(now() at time zone 'utc', 'YYYY-MM-DD'), _left::text)
		);
	end if;
	return _left;
end;
$$;

alter function public.report_bidding_digest_backlog (interval) OWNER to "postgres";

revoke
execute on function public.report_bidding_digest_backlog (interval)
from
	public,
	anon,
	authenticated;

grant
execute on function public.report_bidding_digest_backlog (interval) to service_role;
