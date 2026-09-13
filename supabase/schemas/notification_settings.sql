--------------------------------------
-- Notification preferences
--
-- Three tables and one predicate, answering "may this scholar be sent this notice?".
--
--   public.notification_preferences -- the silenceable keys, and whether each is on for
--                                      someone who has never expressed an opinion.
--   public.optional_emails          -- every silenceable template mapped to the key that
--                                      governs it, so a reminder and the notice it chases
--                                      share one control rather than needing two.
--   public.notification_settings    -- what a particular scholar decided.
--   public.notification_allowed()   -- the one predicate every producer consults.
--
-- What may be silenced is decided in supabase/functions/_shared/templates.ts, where a
-- template carries `optional: true` (or `silencedBy` to defer to another's key). Consequential
-- mail — a charge, a decline, a verification, an assignment — carries no such mark and is
-- always delivered.
--------------------------------------
-- Schema
--
-- The registry, as the database sees it.
--
-- supabase/functions/_shared/templates.ts decides what may be silenced, but it is TypeScript,
-- and the question "may this scholar be sent this?" has to be answered at send time inside
-- public.queue_email. These two tables are that answer: a generated copy of the registry's
-- `optional` / `silencedBy` / `defaultOn` marks, seeded at the bottom of this file by
-- `node scripts/notification-seeds.js` and asserted to match by src/email/templates.unit.ts.
--
-- They are deny-all to clients. Nothing in the interface needs them -- the browser already
-- has the registry itself -- and queue_email reads them as its SECURITY DEFINER owner.
create table if not exists public.notification_preferences (
	-- The preference key. A template key marked `optional` in the registry; the templates that
	-- defer to it via `silencedBy` are listed in public.optional_emails below.
	key text not null,
	-- Whether this preference is on for a scholar with no row in notification_settings.
	--
	-- "Absence is the default, and the default is on" was a fine rule for one notice and a bad
	-- one for two dozen: it would opt every existing scholar into every new notice at once.
	-- The default moved here rather than being backfilled as rows so that adding a preference
	-- is still nothing but a mark on a template.
	default_on boolean not null default true
);

alter table public.notification_preferences OWNER to "postgres";

alter table only public.notification_preferences
add constraint "notification_preferences_pkey" primary key (key);

-- Every silenceable template, mapped to the preference that governs it. A template with no
-- row here is consequential and always sends -- so an accidental omission fails safe, toward
-- delivering mail rather than toward swallowing it.
create table if not exists public.optional_emails (
	-- The template key, as public.emails.event holds it.
	event text not null,
	-- The preference governing it. Equal to `event` for a template that owns its key, and the
	-- target of `silencedBy` for one that defers -- a reminder, or the plural of a notice.
	preference text not null
);

alter table public.optional_emails OWNER to "postgres";

alter table only public.optional_emails
add constraint "optional_emails_pkey" primary key (event);

alter table only public.optional_emails
add constraint "optional_emails_preference_fkey" foreign KEY (preference) references public.notification_preferences (key) on delete cascade;

--------------------------------------
-- Schema
--
-- What a particular scholar decided. A row exists only where a scholar's preference deviates
-- from the registry's default for it.
--
-- The platform's first notification preference, so its shape set the pattern. A boolean
-- column on public.scholars would have been less machinery and was rejected on two counts.
-- Scholar metadata is world readable ("Scholar metadata is public" selects using (true)), so
-- a preference column there publishes everyone's mute list to anyone signed in — and which
-- notices someone has silenced is nobody else's business. And a column can never express
-- "this notice from that venue but not this one", a plausible next ask for someone who leads
-- three venues, whereas adding a nullable `venue` column to this table later does, without a
-- rewrite.
--
-- Absence still means "no opinion", but no longer means "on": the default moved to
-- public.notification_preferences.default_on when this stopped being one notice and became
-- two dozen, because absence-means-on would have opted every existing scholar into all of
-- them at once. There is still nothing to backfill.
create table if not exists public.notification_settings (
	-- The scholar whose preference this is.
	scholar uuid not null,
	-- The template key it governs: a key of `Emails` marked `optional` in
	-- supabase/functions/_shared/templates.ts. Deliberately unconstrained — a CHECK here
	-- would be a second copy of the registry living in SQL and drifting from it, and an
	-- unrecognized key is simply inert, because nothing reads it.
	event text not null,
	-- False to silence it. A row saying true is equivalent to no row, and both are allowed
	-- so the client can write the preference without having to decide whether to delete
	-- the row instead.
	enabled boolean not null,
	-- When the preference was last set.
	created_at timestamp with time zone default now() not null
);

alter table public.notification_settings OWNER to "postgres";

grant all on table public.notification_settings to "anon";

grant all on table public.notification_settings to "authenticated";

grant all on table public.notification_settings to "service_role";

alter table only public.notification_settings
add constraint "notification_settings_pkey" primary key (scholar, event);

alter table only public.notification_settings
add constraint "notification_settings_scholar_fkey" foreign KEY (scholar) references public.scholars (id) on delete cascade;

-- What stops a scholar silencing mail that is not theirs to silence.
--
-- `event` was deliberately unconstrained when this table was written, on the reasoning
-- recorded above that "an unrecognized key is simply inert, because nothing reads it". That
-- stopped being true when public.queue_email began consulting this table: the write policies
-- below carry no column boundary (see the note under Security), so any scholar could have
-- inserted ('me', 'SubmissionCharged', false) and switched off the notice that they had been
-- billed. DESIGN.md makes being told you were charged an accountability property rather than
-- a preference, so the column is now constrained to the keys that are actually silenceable.
--
-- The cost is that marking a template optional now needs a migration, which the original
-- comment promised it would not. That promise was worth less than the guarantee.
alter table only public.notification_settings
add constraint "notification_settings_event_fkey" foreign KEY (event) references public.notification_preferences (key) on delete cascade;

--------------------------------------
-- Security
--
alter table public.notification_settings ENABLE row LEVEL SECURITY;

-- Deliberately NO column-level write boundary here, unlike public.scholars and
-- public.volunteers. Those needed one because a column carried something the row policy did
-- not cover: `steward` is privilege, `orcid` and `email` are identity, `roleid` decided a
-- welcome grant. Every column here is part of "which of my own preferences this is", and
-- the policy below pins the only thing that matters -- a scholar cannot write, or reassign
-- a row to, anybody else. Repointing `event` on one's own row reaches nothing a plain
-- INSERT could not.
--
-- It would also break the ordinary write. PostgREST's upsert compiles to
-- `insert ... on conflict do update set` over EVERY column in the payload, and Postgres
-- checks column privileges for that set-list at plan time -- so revoking `scholar` and
-- `event` makes even the first, non-conflicting insert fail with 42501.
-- Deliberately NOT public, unlike the rest of a scholar's profile. This is the whole reason
-- preferences live in their own table rather than on the world-readable scholars row.
create policy "scholars can read their own notification settings" on public.notification_settings for
select
	to authenticated using (
		scholar=(
			select
				auth.uid ()
		)
	);

create policy "scholars can set their own notification settings" on public.notification_settings for insert to authenticated
with
	check (
		scholar=(
			select
				auth.uid ()
		)
	);

create policy "scholars can change their own notification settings" on public.notification_settings
for update
	to authenticated using (
		scholar=(
			select
				auth.uid ()
		)
	)
with
	check (
		scholar=(
			select
				auth.uid ()
		)
	);

-- Deleting a row restores the default, which is on. Permitted so the client has a way back
-- to "unset" rather than only to "explicitly true".
create policy "scholars can clear their own notification settings" on public.notification_settings for DELETE to authenticated using (
	scholar=(
		select
			auth.uid ()
	)
);

--------------------------------------
-- Security
--
-- Explicitly revoked, not merely un-granted: Supabase's ALTER DEFAULT PRIVILEGES hands anon
-- and authenticated rights on every table created in `public` at creation time, and enabling
-- RLS without policies would still leave those grants sitting there for anyone who later
-- adds one. Same trap as public.token_events and the tokens grants (see ARCHITECTURE.md).
--
-- Nothing client-side reads these: the browser has the registry itself, compiled in.
-- public.queue_email reads them as their owner, which RLS does not apply to.
alter table public.notification_preferences ENABLE row LEVEL SECURITY;

alter table public.optional_emails ENABLE row LEVEL SECURITY;

revoke all on table public.notification_preferences
from
	public,
	anon,
	authenticated;

revoke all on table public.optional_emails
from
	public,
	anon,
	authenticated;

grant
select
	on table public.notification_preferences to service_role;

grant
select
	on table public.optional_emails to service_role;

--------------------------------------
-- RPC
--
-- May this scholar be sent this notice?
--
-- The single place the question is answered, so that every producer answers it the same way.
-- Before this, the registry declared that each producer was responsible for consulting
-- public.notification_settings itself, and exactly one of them ever did -- which is the real
-- reason the scholar profile could only ever show one checkbox.
--
-- False only for a template that IS silenceable and whose governing preference resolves off.
-- A consequential template has no public.optional_emails row, matches nothing, and returns
-- true -- so a template accidentally missing from the seed keeps sending rather than going
-- quiet, which is the safer way to be wrong about mail.
create or replace function public.notification_allowed (_scholar uuid, _event text) returns boolean language sql stable security definer
set
	"search_path" to 'public',
	'pg_temp' as $$
select
	not exists (
		select 1
		from public.optional_emails o
		join public.notification_preferences p on p.key = o.preference
		left join public.notification_settings n on n.scholar = _scholar
		and n.event = o.preference
		where o.event = _event
			and not coalesce(n.enabled, p.default_on)
	);
$$;

alter function public.notification_allowed (uuid, text) OWNER to "postgres";

-- Explicitly revoked, not merely un-granted: Supabase's ALTER DEFAULT PRIVILEGES hands anon
-- and authenticated EXECUTE on every function created in `public` at creation time, and
-- `revoke ... from public` does not take those back. See 20260831000000. This one reads
-- tables that are deny-all to clients, so leaving it open would publish whose mute list says
-- what, one probe at a time.
revoke
execute on function public.notification_allowed (uuid, text)
from
	public,
	anon,
	authenticated;

grant
execute on function public.notification_allowed (uuid, text) to service_role;

--------------------------------------
-- Seed
--
-- GENERATED. Do not hand-edit: run `node scripts/notification-seeds.js` and paste, and put
-- the same block in a migration. src/email/templates.unit.ts asserts this matches the
-- registry, because a stale copy here mails people notices they switched off.
insert into
	public.notification_preferences (key, default_on)
values
	('AvailabilityReminder', true),
	('CompensationChanged', true),
	('CompensationRequested', true),
	('ConflictDeclared', false),
	('InviteAccepted', true),
	('NewBid', true),
	('NewVolunteer', true),
	('ProposalSupported', true),
	('SubmissionClaimed', true),
	('SubmissionDone', true),
	('SubmissionsNeedEditors', true),
	('SubmissionsReady', true),
	('ThanksPendingReview', true),
	('ThanksReceived', true),
	('ThanksShared', true),
	('TokensMinted', false),
	('TokensReceived', true),
	('TransactionApproved', true),
	('TransactionsPending', true),
	('VenueApproved', true),
	('VenueDeactivated', true),
	('VolunteerPaused', false)
on conflict (key) do update
set
	default_on=excluded.default_on;

insert into
	public.optional_emails (event, preference)
values
	('AvailabilityReminder', 'AvailabilityReminder'),
	('CompensationChanged', 'CompensationChanged'),
	('CompensationPending', 'CompensationRequested'),
	('CompensationRequested', 'CompensationRequested'),
	('ConflictDeclared', 'ConflictDeclared'),
	('InviteAccepted', 'InviteAccepted'),
	('InviteDeclined', 'InviteAccepted'),
	('NewBid', 'NewBid'),
	('NewVolunteer', 'NewVolunteer'),
	('ProposalDeclined', 'VenueApproved'),
	('ProposalSupported', 'ProposalSupported'),
	('SubmissionClaimed', 'SubmissionClaimed'),
	('SubmissionDone', 'SubmissionDone'),
	('SubmissionNeedsEditor', 'SubmissionsNeedEditors'),
	(
		'SubmissionsNeedEditors',
		'SubmissionsNeedEditors'
	),
	('SubmissionsReady', 'SubmissionsReady'),
	('ThanksPendingReview', 'ThanksPendingReview'),
	('ThanksReceived', 'ThanksReceived'),
	('ThanksShared', 'ThanksShared'),
	('TokensMinted', 'TokensMinted'),
	('TokensReceived', 'TokensReceived'),
	('TransactionApproved', 'TransactionApproved'),
	('TransactionsPending', 'TransactionsPending'),
	('VenueApproved', 'VenueApproved'),
	('VenueDeactivated', 'VenueDeactivated'),
	('VenueReactivated', 'VenueDeactivated'),
	('VolunteerPaused', 'VolunteerPaused'),
	('VolunteerResumed', 'VolunteerPaused')
on conflict (event) do update
set
	preference=excluded.preference;

delete from public.optional_emails
where
	event not in (
		'AvailabilityReminder',
		'CompensationChanged',
		'CompensationPending',
		'CompensationRequested',
		'ConflictDeclared',
		'InviteAccepted',
		'InviteDeclined',
		'NewBid',
		'NewVolunteer',
		'ProposalDeclined',
		'ProposalSupported',
		'SubmissionClaimed',
		'SubmissionDone',
		'SubmissionNeedsEditor',
		'SubmissionsNeedEditors',
		'SubmissionsReady',
		'ThanksPendingReview',
		'ThanksReceived',
		'ThanksShared',
		'TokensMinted',
		'TokensReceived',
		'TransactionApproved',
		'TransactionsPending',
		'VenueApproved',
		'VenueDeactivated',
		'VenueReactivated',
		'VolunteerPaused',
		'VolunteerResumed'
	);

delete from public.notification_preferences
where
	key not in (
		'AvailabilityReminder',
		'CompensationChanged',
		'CompensationRequested',
		'ConflictDeclared',
		'InviteAccepted',
		'NewBid',
		'NewVolunteer',
		'ProposalSupported',
		'SubmissionClaimed',
		'SubmissionDone',
		'SubmissionsNeedEditors',
		'SubmissionsReady',
		'ThanksPendingReview',
		'ThanksReceived',
		'ThanksShared',
		'TokensMinted',
		'TokensReceived',
		'TransactionApproved',
		'TransactionsPending',
		'VenueApproved',
		'VenueDeactivated',
		'VolunteerPaused'
	);
