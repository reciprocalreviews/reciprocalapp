-- The ORCID profile mirror: a cache of the narrow, review-relevant slice of a
-- scholar's public ORCID record, so an editor choosing a reviewer can see who
-- someone is without opening orcid.org in another tab.
--
-- Paired with supabase/schemas/orcid_profiles.sql, which is the declarative source
-- of truth. The two must stay identical: only migrations run on a reset, and CI
-- checks the schemas against them.

--------------------------------------
-- ORCID profile mirror
--
-- A cache of the narrow, review-relevant slice of a scholar's PUBLIC ORCID record, so an
-- editor choosing a reviewer can see who someone is without opening orcid.org in another
-- tab. See DESIGN.md's Scholar route section for what is mirrored and what deliberately
-- is not, and ARCHITECTURE.md's "ORCID profile mirror" for how it is filled.
--
-- Three properties are worth stating up front, because the rest of this file follows from
-- them:
--
--   1. It is DERIVED. Every row can be rebuilt by re-fetching, which is why it is not
--      audited, not in the realtime publication, and hard-deleted rather than scrubbed on
--      erasure.
--   2. It is already PUBLIC. The ORCID public API returns only items the scholar set to
--      public visibility, so ORCID's own privacy setting is the consent mechanism and
--      there is no RR-side toggle to explain.
--   3. Nobody may WRITE it, not even about themselves. The section's whole value is that
--      it says what ORCID says; a writable mirror would be a claim RR was vouching for.

create table if not exists
	public.orcid_profiles (
		-- Keyed on the scholar rather than the iD, so PostgREST can embed it from any
		-- query that already has scholars in it.
		scholar uuid not null,
		-- The iD this cache was fetched FOR. Deliberately not derived at read time from
		-- scholars.orcid: erasure nulls that column, so a row whose contents came from an
		-- iD the scholar no longer holds has to be detectable rather than silently
		-- re-attributed to whoever holds the row now.
		orcid text not null,
		-- Current affiliation. Three columns rather than one rendered string, because the
		-- roster and the assignment table show different subsets of it -- the table drops
		-- the department, which is the least discriminating part and the narrowest cell --
		-- and joining them in SQL would take that choice away.
		employment_role text,
		employment_department text,
		employment_organization text,
		-- Most recent education, as a seniority signal: a first-year PhD student and a
		-- senior researcher carry very different reviewing-load norms.
		education_role text,
		education_organization text,
		education_year smallint,
		-- Self-declared topics. An array rather than child rows because the volunteers
		-- roster does all of its keyword work in JavaScript over rows already in memory,
		-- so child rows would add an embed and buy no capability. A GIN index makes this
		-- server-side filterable later without restructuring.
		keywords text[] not null default '{}',
		-- The few most recent works: [{ title, year, journal, doi, url }]. jsonb rather
		-- than child rows because it is bounded, display-only, and never filtered or
		-- aggregated in SQL -- the aggregates below are computed over the FULL set, which
		-- child rows holding only these could not produce.
		works jsonb not null default '[]',
		-- Counted over every work in the record. Nullable, and null is NOT 0: null means
		-- the works section has not been read, 0 means it was read and is empty. The
		-- interface branches on the difference.
		work_count integer,
		work_first_year smallint,
		work_last_year smallint,
		-- Researcher urls and external identifiers: [{ kind, label, value, url }].
		links jsonb not null default '[]',
		-- Two clocks, because /works is the only expensive fetch: 787KB uncompressed for a
		-- prolific record against 8.3KB for the other three sections combined.
		fetched_at timestamptz,
		works_fetched_at timestamptz,
		-- The claim stamp, written BEFORE the fetch is asked for. That ordering is the
		-- whole reason the cooldown is a stampede guard rather than a hope: ten editors
		-- opening the same roster claim once between them, not ten times.
		fetch_attempted_at timestamptz not null default now(),
		fetch_status text not null default 'pending',
		-- Consecutive failures, for backoff. Reset to zero on success.
		fetch_failures smallint not null default 0,
		-- Diagnostics for whoever is looking at the row. NEVER rendered to a visitor, for
		-- the same reason emails.delivery_detail is not.
		fetch_detail text
	);

alter table public.orcid_profiles owner to "postgres";

alter table only public.orcid_profiles
add constraint orcid_profiles_pkey primary key (scholar);

alter table only public.orcid_profiles
add constraint orcid_profiles_scholar_fkey foreign key (scholar) references public.scholars (id) on delete cascade;

-- A four-value vocabulary, enforced rather than conventional, following
-- emails_delivery_status: the interface branches on these exact words.
--   pending   -- claimed, no answer yet
--   ok        -- fetched and parsed
--   not_found -- ORCID answered 404/409: no such record, or deactivated
--   error     -- 5xx, 429, timeout, or unparseable
alter table only public.orcid_profiles
add constraint orcid_profiles_fetch_status check (
	fetch_status in ('pending', 'ok', 'not_found', 'error')
);

-- Bounded here rather than trusted from the writer. The writer is a separately deployed
-- edge function, which can go stale against this schema between deploys.
alter table only public.orcid_profiles
add constraint orcid_profiles_works_bounded check (jsonb_array_length(works) <= 5);

-- Both payload columns are arrays. Without this a scalar or object would satisfy the
-- column type and break every reader that iterates them.
alter table only public.orcid_profiles
add constraint orcid_profiles_shapes check (
	jsonb_typeof(works) = 'array'
	and jsonb_typeof(links) = 'array'
);

-- The claim query's driving scan: "who is stale and out of cooldown".
create index if not exists orcid_profiles_attempted_index on public.orcid_profiles using btree (fetch_attempted_at);

--------------------------------------
-- Security
--
alter table public.orcid_profiles enable row level security;

-- Explicitly revoked, not merely un-granted: Supabase's default privileges hand anon and
-- authenticated ALL on every new table in `public` before this line runs. The same
-- correction token_events and erasures make.
revoke all on table public.orcid_profiles
from
	anon,
	authenticated;

grant
select
	on table public.orcid_profiles to anon,
	authenticated;

grant all on table public.orcid_profiles to service_role;

-- World-readable, exactly as scholars is, and for a stronger reason: every field here is
-- already published at orcid.org under the scholar's own visibility setting, so withholding
-- it would protect nothing while making the mirror disagree with its source. It is also
-- what makes the volunteers roster and the assignment table possible at all -- both render
-- rows for scholars the viewer has no relationship to.
create policy "ORCID profiles are public" on public.orcid_profiles for
select
	to authenticated,
	anon using (true);

-- No INSERT, UPDATE or DELETE policy, deliberately. The only writer is the `orcid` edge
-- function running as service_role, which bypasses RLS. A scholar cannot edit this for the
-- same reason they cannot edit scholars.orcid.

--------------------------------------
-- Refreshing
--
-- The shape here is the one send_email() established: a database-side event fires a
-- best-effort net.http_post at an edge function carrying the secret_key on the `apikey`
-- header, records that it was asked for, and never rolls back the caller. Delivery is a
-- deployment concern and must not be able to fail a page load or a sign-in.
--
-- Staleness lives HERE and nowhere else. TypeScript never computes it; the interface only
-- reads fetched_at to render an "as of" date. One source of truth for how old is too old.

-- How many scholars travel in one post to the edge function. The function fetches three
-- to four ORCID endpoints per scholar, and the anonymous public API allows 12 requests a
-- second, so a batch of twenty is a few seconds of work for it.
create or replace function private.orcid_batch_size () returns integer language sql immutable
set
	search_path = '' as $$ select 20 $$;

alter function private.orcid_batch_size () owner to "postgres";

/**
 * Claim a set of scholars for refresh and ask the edge function to fetch them.
 *
 * Returns how many were claimed. Claiming is what makes the cooldown work: the stamp is
 * written before the fetch is requested, so concurrent readers of the same roster produce
 * one fetch per scholar per cooldown rather than one per reader.
 *
 * `_force` bypasses the staleness clocks but NOT the cooldown, so no caller -- not a
 * sign-in, not a backfill, not a button -- can turn this into a flood of ORCID traffic.
 */
create or replace function private.claim_orcid_refresh (_ids uuid[], _force boolean default false) returns integer language plpgsql security definer
set
	search_path = '' as $$
declare
	-- btrim so a secret pasted with a stray newline still works.
	_key text := btrim(coalesce(private.get_secret('secret_key'), ''));
	_url text := btrim(coalesce(private.get_secret('supabase_url'), ''));
	_claimed uuid[];
	_batch jsonb;
	_size integer := private.orcid_batch_size();
	_offset integer := 0;
begin
	if _ids is null or cardinality(_ids) = 0 then return 0; end if;

	-- Claim. A scholar with no iD is skipped rather than failed: that is an erased
	-- tombstone or a seeded fixture, and there is nothing to fetch for either. This is
	-- also the first of the two guards that stop a batch claimed just before an erasure
	-- from writing the row back after it -- the second is in the edge function, which
	-- re-reads scholars.orcid at write time.
	with candidates as (
		select s.id, s.orcid
		from public.scholars s
		left join public.orcid_profiles p on p.scholar = s.id
		where s.id = any (_ids)
			and s.orcid is not null
			-- Out of cooldown. Coalesced to -infinity so a row that has never been
			-- attempted is always eligible.
			and coalesce(p.fetch_attempted_at, '-infinity'::timestamptz) < now() - interval '6 hours'
			and (
				_force
				or p.scholar is null
				-- The profile sections, on a 30 day clock.
				or p.fetched_at is null
				or p.fetched_at < now() - interval '30 days'
				-- Works, on a 90 day clock of their own: they are the expensive fetch.
				or p.works_fetched_at is null
				or p.works_fetched_at < now() - interval '90 days'
			)
	), claimed as (
		insert into public.orcid_profiles as p (scholar, orcid, fetch_attempted_at, fetch_status)
		select c.id, c.orcid, now(), 'pending' from candidates c
		on conflict (scholar) do update set
			fetch_attempted_at = now(),
			-- Follow a scholar whose iD changed, so the row cannot keep serving contents
			-- fetched for somebody else's record.
			orcid = excluded.orcid
		returning p.scholar
	)
	select array_agg(scholar) into _claimed from claimed;

	if _claimed is null or cardinality(_claimed) = 0 then return 0; end if;

	-- Nothing to post to. The rows stay claimed and terminally 'pending', which the next
	-- attempt after the cooldown will pick up again.
	if _key = '' or _url = '' then
		raise warning 'claim_orcid_refresh: % is not configured, so % profiles were claimed but not fetched',
			case when _url = '' then 'the supabase_url vault secret' else 'the secret_key vault secret' end,
			cardinality(_claimed);
		return cardinality(_claimed);
	end if;

	-- Post in batches. A backfill can claim far more than one batch, and the edge function
	-- paces itself within a batch but cannot pace across an unbounded one.
	while _offset < cardinality(_claimed) loop
		select jsonb_agg(
			jsonb_build_object(
				'scholar', p.scholar,
				'orcid', p.orcid,
				-- Per scholar, so the expensive section is asked for only when its own
				-- clock expired rather than on every profile refresh.
				'works', (p.works_fetched_at is null or p.works_fetched_at < now() - interval '90 days')
			)
		) into _batch
		from public.orcid_profiles p
		where p.scholar = any (_claimed[_offset + 1 : _offset + _size]);

		begin
			-- If the supabase URL is localhost, rewrite it so the container reaches the
			-- host machine. The key goes on `apikey`: Authorization: Bearer is reserved
			-- for JWTs and the opaque sb_secret_... keys are rejected there.
			perform net.http_post(
				url := replace(_url, '127.0.0.1', 'host.docker.internal') || '/functions/v1/orcid',
				headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', _key)::jsonb,
				body := jsonb_build_object('scholars', _batch)
			);
		exception when others then
			-- pg_net validates the URL synchronously, so a malformed value raises here
			-- rather than in the background worker. Warn and carry on: the rows are
			-- claimed, and the next attempt after the cooldown will try again.
			raise warning 'claim_orcid_refresh: could not queue a batch: % (%)', sqlerrm, sqlstate;
		end;

		_offset := _offset + _size;
	end loop;

	return cardinality(_claimed);
end;
$$;

alter function private.claim_orcid_refresh (uuid[], boolean) owner to "postgres";

revoke execute on function private.claim_orcid_refresh (uuid[], boolean)
from
	public,
	anon,
	authenticated;

/**
 * Refresh a handful of scholars, for a page that has just rendered them.
 *
 * Called without awaiting it, from the browser, after paint -- never from a `load`, which
 * would put ORCID's availability on the critical path of a page that has a dozen queries
 * already. Every surface renders whatever the cache holds right now, possibly nothing, and
 * this lands for the next reader.
 */
create or replace function public.request_orcid_refresh (_scholars uuid[], _force boolean default false) returns integer language plpgsql security definer
set
	search_path = '' as $$
declare
	_ids uuid[];
begin
	if (select auth.uid()) is null then
		raise exception 'Authentication required';
	end if;
	if _scholars is null then return 0; end if;

	-- Clamped, and distinct, so one call cannot be turned into an unbounded fan-out by a
	-- caller that passes every scholar it can name.
	select array_agg(id) into _ids from (
		select distinct s as id from unnest(_scholars) s limit (select private.orcid_batch_size())
	) capped;

	return private.claim_orcid_refresh(_ids, _force);
end;
$$;

alter function public.request_orcid_refresh (uuid[], boolean) owner to "postgres";

revoke execute on function public.request_orcid_refresh (uuid[], boolean)
from
	public,
	anon;

-- Ordinary RPC: authenticated only. Anonymous visitors deliberately do not warm the cache
-- -- an anon visitor to a cold profile sees the ORCID link and nothing else. The editors
-- this feature is for are always signed in, and leaving it out closes a crawler-driven
-- path into ORCID's daily budget.
grant
execute on function public.request_orcid_refresh (uuid[], boolean) to authenticated;

/**
 * Populate profiles that have never been fetched, oldest attempt first.
 *
 * The bootstrap. Without it every row is cold on the day this ships and stays cold until
 * its scholar signs in or somebody opens a page showing them -- so the editors the mirror
 * exists for would see an empty section for months.
 *
 * Steward-gated and re-runnable: the cooldown and the staleness clocks make a second run
 * claim only what the first did not, so it can be called repeatedly until it returns 0.
 * `_limit` is what paces it against ORCID's daily budget -- roughly four requests per
 * scholar, against 25k a day unauthenticated.
 */
create or replace function public.backfill_orcid_profiles (_limit integer default 100) returns integer language plpgsql security definer
set
	search_path = '' as $$
declare
	_ids uuid[];
begin
	if not public.isSteward() then
		raise exception 'Only a steward can backfill ORCID profiles' using errcode = 'RR006';
	end if;

	-- Never-fetched rows first, then the longest-unattempted. That ordering is what makes
	-- a paced backfill converge: each run takes the oldest slice rather than re-walking
	-- the same head of the table.
	select array_agg(id) into _ids from (
		select s.id
		from public.scholars s
		left join public.orcid_profiles p on p.scholar = s.id
		where s.orcid is not null
			and (p.scholar is null or p.fetched_at is null or p.fetched_at < now() - interval '30 days')
			and coalesce(p.fetch_attempted_at, '-infinity'::timestamptz) < now() - interval '6 hours'
		order by p.fetched_at asc nulls first, p.fetch_attempted_at asc nulls first
		limit least(greatest(coalesce(_limit, 100), 1), 500)
	) due;

	return private.claim_orcid_refresh(_ids, false);
end;
$$;

alter function public.backfill_orcid_profiles (integer) owner to "postgres";

revoke execute on function public.backfill_orcid_profiles (integer)
from
	public,
	anon;

-- Steward-gated rather than owner-only: a steward runs this from the SQL editor or a
-- script after a deploy, so it needs to be callable as a signed-in user. The isSteward()
-- check inside is the gate; the grant only decides who may reach it.
grant
execute on function public.backfill_orcid_profiles (integer) to authenticated;

--------------------------------------
-- Data rights
--
-- The mirror is person-data the platform holds, so it travels with the two promises
-- DESIGN.md makes unconditionally: a scholar can download everything, and a scholar can
-- erase everything.
--
-- Both functions are re-created in full below rather than patched, because that is the
-- only way plpgsql bodies change -- and the grants travel WITH them, since Supabase's
-- default privileges re-open EXECUTE to anon and authenticated on every create or
-- replace. supabase/tests/rls/definer_grants.sql is what catches that if it is forgotten.

create or replace function public.forget_scholar (_scholar uuid) returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_placeholder text := 'erased-' || _scholar || '@invalid';
	_emails int;
	_copied int;
	_audit int;
	_old_email text;
	-- How many ORCID mirror rows went with them. Always 0 or 1; reported because the
	-- receipt is what an erasure request is answered with.
	_orcid integer := 0;
begin
	if _scholar is null then
		raise exception 'forget_scholar requires a scholar id';
	end if;

	-- Captured BEFORE the scholars row below is scrubbed. Mail where this scholar was
	-- merely copied, or was the person replies went to, is reachable only by address:
	-- emails.cc and emails.reply_to hold addresses, and neither is matched by the
	-- scholar/sender scrub further down.
	select email into _old_email from public.scholars where id = _scholar;

	-- The identity behind the account. The row stays so the foreign keys hold, but
	-- nothing in it points at a person any more, and the credentials are destroyed
	-- so the account cannot be used again.
	update auth.users
	set
		email = _placeholder,
		phone = null,
		encrypted_password = null,
		raw_user_meta_data = '{}'::jsonb,
		raw_app_meta_data = '{}'::jsonb,
		confirmation_token = '',
		recovery_token = '',
		email_change = ''
	where id = _scholar;

	-- ORCID is the login identity; `status` is free text the scholar wrote about
	-- themselves and can name anyone.
	update public.scholars
	set
		name = null,
		email = null,
		orcid = null,
		-- Erasure destroys the identity, so it must destroy the privilege with it. A
		-- tombstone that is still a steward appears on the public /about list as
		-- "anonymous", still satisfies isSteward(), and would satisfy set_steward's
		-- last-steward guard on behalf of a uuid nobody can sign into — letting the
		-- last real steward be demoted while nobody is left who can act.
		steward = false,
		-- Emptied rather than nulled: `status` is NOT NULL. It is free text the
		-- scholar wrote about themselves and can name anyone, so it has to go.
		status = '',
		available = false
	where id = _scholar;

	-- The verification email itself. It is attributed to NOBODY — null scholar, null sender,
	-- so that no branch of the emails SELECT policy matches it and the requester cannot read
	-- the token back out of `args` — which means the redaction pass below, keyed on exactly
	-- those two columns, has never touched it. An erased scholar's unverified candidate
	-- address therefore survived in `email`, and the raw verification URL in `args`,
	-- indefinitely. email_verifications.email_id is what makes it findable (#27).
	--
	-- Runs BEFORE the delete below, because it reads the row being deleted.
	update public.emails
	set
		email = _placeholder,
		args = '[]'::jsonb
	where
		id in (
			select email_id from public.email_verifications
			where scholar = _scholar and email_id is not null
		);

	-- A pending verification holds an address that was never even confirmed.
	delete from public.email_verifications where scholar = _scholar;

	-- The ORCID mirror: a cached copy of their name's worth of public record --
	-- affiliation, keywords, recent publications. A hard DELETE rather than a scrub,
	-- and the one table here that gets one, because it is DERIVED: nothing references
	-- it and it can be rebuilt by re-fetching, so there is no reason to keep a husk.
	--
	-- The foreign key is ON DELETE CASCADE and that is NOT enough on its own. Erasure
	-- anonymises the scholar row in place rather than deleting it, so no cascade ever
	-- fires -- the same reason email_verifications is deleted by hand above.
	--
	-- The scholars UPDATE below nulls `orcid`, which is what stops the row coming back:
	-- claim_orcid_refresh skips a scholar with no iD, and the edge function re-reads the
	-- iD before writing, so a batch claimed moments before this runs writes nothing.
	with dropped as (
		delete from public.orcid_profiles where scholar = _scholar returning 1
	) select count(*) into _orcid from dropped;

	-- Queued and sent mail carries the address and, in `args`, rendered values that
	-- can include their name. The row stays as evidence that a message was sent;
	-- its contents do not.
	update public.emails
	set
		email = _placeholder,
		subject = null,
		message = null,
		args = '[]'::jsonb,
		-- Mail addressed TO this scholar may also have copied others and named a third
		-- party as its reply address. Neither belongs to the erased scholar, but both are
		-- contents of a message whose contents are being destroyed.
		cc = null,
		reply_to = null
	where scholar = _scholar or sender = _scholar;
	get diagnostics _emails = row_count;

	-- Mail about SOMEBODY ELSE that merely copied this scholar, or that replied to them.
	-- The rest of the row belongs to other people and stays; only this scholar's address
	-- leaves it. Without this pass an erased address survived indefinitely in notices about
	-- other scholars — the exact thing erasure exists to prevent.
	if _old_email is not null then
		update public.emails
		set
			cc = nullif(array_remove(cc, _old_email), '{}'::text[]),
			reply_to = case when reply_to = _old_email then null else reply_to end
		where (cc is not null and _old_email = any (cc))
			or reply_to = _old_email;
		get diagnostics _copied = row_count;
	else
		_copied := 0;
	end if;

	-- audit_log keeps WHOLE rows, so every edit this scholar's profile ever
	-- received contains their name and address. Scrub the payloads and the actor,
	-- leaving which table changed and when — the append-only guard permits exactly
	-- this much and nothing more.
	perform set_config('app.erasure', 'on', true);

	update public.audit_log
	set
		before = case when before is not null then '{}'::jsonb end,
		after = case when after is not null then '{}'::jsonb end
	where tbl = 'scholars' and row_id = _scholar;
	get diagnostics _audit = row_count;

	update public.audit_log set actor = null where actor = _scholar;

	-- token_events.actor is the only field here that names a person; the ownership
	-- columns are left untouched, because the ledger is reconstructed from them.
	update public.token_events set actor = null where actor = _scholar;

	perform set_config('app.erasure', '', true);

	insert into public.erasures (subject, completed_at)
	values (_scholar, now())
	on conflict (subject) do update set completed_at = now();

	return jsonb_build_object(
		'scholar', _scholar,
		'emails_scrubbed', _emails,
		-- Reported separately from emails_scrubbed: these rows were not scrubbed, only
		-- de-addressed, and the receipt should not imply that mail about other people was
		-- emptied out.
		'emails_uncopied', _copied,
		'audit_payloads_scrubbed', _audit,
		'orcid_profile_deleted', _orcid
	);
end;
$$;

alter function public.forget_scholar (uuid) OWNER to "postgres";

revoke
execute on function public.forget_scholar (uuid)
from
	public,
	anon,
	authenticated,
	service_role;

--------------------------------------
-- The scholar-facing entry point. A scholar may erase themselves; a steward may
-- erase anyone, for a request that arrives by post or by email.

create or replace function public.export_scholar_data (_scholar uuid default null) returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_caller uuid := (select auth.uid());
	_target uuid := coalesce(_scholar, _caller);
	_target_email text;
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	if _target <> _caller and not public.isSteward() then
		raise exception 'You can only export your own data' using errcode = 'RR006';
	end if;

	-- Resolved once rather than per row: emails.cc holds addresses, not ids.
	select email into _target_email from public.scholars s where s.id = _target;

	return jsonb_build_object(
		'exported_at', now(),
		'scholar', (select to_jsonb(s) from public.scholars s where s.id = _target),
		'volunteering', (select coalesce(jsonb_agg(to_jsonb(v)), '[]'::jsonb) from public.volunteers v where v.scholarid = _target),
		'submissions', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.submissions x where _target = any (x.authors)),
		'assignments', (select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) from public.assignments a where a.scholar = _target),
		'conflicts', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from public.conflicts c where c.scholarid = _target),
		'supported_proposals', (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from public.supporters p where p.scholarid = _target),
		'thanks_written', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.thanks t where t.author = _target),
		'transactions', (select coalesce(jsonb_agg(to_jsonb(t) order by t.seq), '[]'::jsonb) from public.transactions t
			where t.creator = _target or t.from_scholar = _target or t.to_scholar = _target),
		'tokens_held', (select coalesce(jsonb_object_agg(currency, n), '{}'::jsonb)
			from (select currency, count(*) as n from public.tokens where scholar = _target group by currency) c),
		-- The ledger makes this possible for the first time: before token_events
		-- there was no record of where a scholar's tokens had been.
		'token_history', (select coalesce(jsonb_agg(to_jsonb(e) order by e.seq), '[]'::jsonb)
			from public.token_events e where e.scholar = _target or e.prev_scholar = _target),
		-- Addressed to them, or copied on it. `m.scholar` names only the To recipient, so
		-- before the cc branch a scholar's own export said nothing about notices they
		-- actually received. SECURITY DEFINER, so this scan is not limited by the emails
		-- SELECT policy — which is what lets it report mail the scholar received but cannot
		-- read the row for. Still only the event and the time: the export says what
		-- arrived, not what it said.
		'emails_received', (select coalesce(jsonb_agg(jsonb_build_object('event', m.event, 'time_sent', m.time_sent)), '[]'::jsonb)
			from public.emails m
			where m.scholar = _target
				or (_target_email is not null and m.cc is not null and _target_email = any (m.cc))),
		-- Which notices they have silenced. Small, but it is a preference they set, and so
		-- part of what the platform holds about them.
		'notification_settings', (select coalesce(jsonb_agg(to_jsonb(n)), '[]'::jsonb)
			from public.notification_settings n where n.scholar = _target),
		-- The ORCID mirror. Arguably redundant -- it is a copy of their own public ORCID
		-- record, which they can get from ORCID -- but the promise is everything the
		-- platform holds about them, the platform holds this, and an export that quietly
		-- omitted a section their profile page displays would be a broken promise found
		-- by whoever compared the two.
		'orcid_profile', (select to_jsonb(p) from public.orcid_profiles p where p.scholar = _target)
	);
end;
$$;

alter function public.export_scholar_data (uuid) OWNER to "postgres";

revoke
execute on function public.export_scholar_data (uuid)
from
	public,
	anon;

grant
execute on function public.export_scholar_data (uuid) to authenticated;
