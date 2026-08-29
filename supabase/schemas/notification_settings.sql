--------------------------------------
-- Schema
--
-- Per-scholar notification preferences: which of the platform's OPTIONAL emails a scholar
-- would rather not receive.
--
-- The platform's first notification preference, so its shape sets the pattern. A boolean
-- column on public.scholars would have been less machinery and was rejected on two counts.
-- Scholar metadata is world readable ("Scholar metadata is public" selects using (true)), so
-- a preference column there publishes everyone's mute list to anyone signed in — and which
-- notices someone has silenced is nobody else's business. And a column can never express
-- "this notice from that venue but not this one", a plausible next ask for someone who leads
-- three venues, whereas adding a nullable `venue` column to this table later does, without a
-- rewrite.
--
-- Absence is the default, and the default is on. There is no row until a scholar turns
-- something off, so there is nothing to backfill, and a template marked `optional` later
-- needs no migration at all.
--
-- What may be silenced is decided in supabase/functions/_shared/templates.ts, where a
-- template carries `optional: true`. Consequential mail — a charge, a decline, a
-- verification, an assignment — carries no such flag and is always delivered.
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
