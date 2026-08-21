-- Apply an hourly tail to a freshly restored database.
--
-- Run by supabase/dr/replay.sh, which mounts the tail directory at /tail and
-- passes the watermark:
--
--     psql "$URL" -v from_seq=63 -f replay.sql
--
-- `from_seq` is `db.watermarks.audit_log` from the manifest of the dump you just
-- restored: everything at or below it is already present, everything above it is
-- what this applies.
--
-- Kept as its own file rather than a heredoc inside the shell script. \copy is a
-- psql meta-command, so it cannot be passed with `psql -c`, and wrapping it in
-- shell quoting buys nothing but a layer to get wrong.
\set ON_ERROR_STOP on

-- Suppress every user trigger for this session. replay_audit_log refuses to run
-- without it: replaying with triggers live would manufacture a fresh audit_log
-- and token_events entry for every row applied, fabricating a history in which
-- the whole economy moved at the moment of the restore.
set session_replication_role = replica;

-- REPLAY BEFORE ANYTHING ELSE WRITES. `seq` is an identity column, so after a
-- restore it resumes from the restored maximum — and any write that happens in
-- between takes the very seq values the tail is carrying. Deduplicating on seq
-- would then silently discard the tail's real rows as "already present", and the
-- replay would report success having applied someone else's writes.
--
-- That is not hypothetical: it happened here first time, because rearm.sql stamps
-- every scholar's reminder timestamp and those ten writes took seq 64-73 — exactly
-- the range the tail held. Hence this guard, and hence replay coming BEFORE the
-- re-arm step in RECOVERY.md rather than after.
-- Passed through a setting because psql does not substitute :variables inside a
-- dollar-quoted body.
select
	set_config('dr.from_seq', :'from_seq', false);

do $$
declare
	_max bigint;
	_want bigint := current_setting('dr.from_seq')::bigint;
begin
	select coalesce(max(seq), 0) into _max from public.audit_log;
	if _max <> _want then
		raise exception
			'audit_log is at seq % but the restored dump ended at %; something has written since the restore, so replaying now would collide. Restore again and replay before re-arming.',
			_max, _want;
	end if;
end;
$$;

begin;

-- The tail's windows overlap on purpose, so rows already present are expected
-- rather than exceptional. Dedupe on seq, which is safe only because the guard
-- above established that nothing has written since the restore.
create temp table _tail_audit (like public.audit_log including defaults) on commit drop;

\copy _tail_audit from '/tail/audit_log.csv' (format csv, header)

insert into public.audit_log
overriding system value
select
	*
from
	_tail_audit t
where
	not exists (
		select
			1
		from
			public.audit_log a
		where
			a.seq=t.seq
	);

create temp table _tail_events (like public.token_events including defaults) on commit drop;

\copy _tail_events from '/tail/token_events.csv' (format csv, header)

insert into public.token_events
overriding system value
select
	*
from
	_tail_events t
where
	not exists (
		select
			1
		from
			public.token_events e
		where
			e.seq=t.seq
	);

-- A scholar who signed up inside the window has a public.scholars row in
-- audit_log and an auth.users row nowhere. scholars.id references auth.users(id),
-- so without these the replay fails on the foreign key.
create temp table _tail_users (like auth.users) on commit drop;

\copy _tail_users from '/tail/auth_users.csv' (format csv, header)

-- Columns enumerated dynamically, skipping GENERATED ones: auth.users has at
-- least one (confirmed_at on users), and `insert ... select *` into a generated
-- column is rejected outright. Reading the list from the catalogue rather than
-- hardcoding it keeps this working when Supabase changes the auth schema.
do $$
declare
	_cols text;
begin
	select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
	into _cols
	from information_schema.columns
	where table_schema = 'auth' and table_name = 'users' and is_generated <> 'ALWAYS';

	execute format(
		'insert into auth.users (%s) select %s from _tail_users t where not exists (select 1 from auth.users x where x.id = t.id)',
		_cols, _cols
	);
end;
$$;

create temp table _tail_idents (like auth.identities) on commit drop;

\copy _tail_idents from '/tail/auth_identities.csv' (format csv, header)

-- Columns enumerated dynamically, skipping GENERATED ones, for the same reason as
-- auth.users above: `insert ... select *` into a generated
-- column is rejected outright. Reading the list from the catalogue rather than
-- hardcoding it keeps this working when Supabase changes the auth schema.
do $$
declare
	_cols text;
begin
	select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
	into _cols
	from information_schema.columns
	where table_schema = 'auth' and table_name = 'identities' and is_generated <> 'ALWAYS';

	execute format(
		'insert into auth.identities (%s) select %s from _tail_idents t where not exists (select 1 from auth.identities x where x.id = t.id)',
		_cols, _cols
	);
end;
$$;

commit;

-- Rewrite the audited tables to the state they were in when the tail was taken.
select
	jsonb_pretty(public.replay_audit_log (:from_seq));
