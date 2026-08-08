-- An append-only record of every change to the mutable state tables.
--
-- WHY
--
-- token_events (20260804010000) makes the token economy reconstructible, but it
-- covers exactly one table. Everything else — who edited a venue's settings, who
-- was added as an admin or minter, which submission changed type, which
-- assignment was deleted — has no history at all: the row is simply overwritten,
-- and a DELETE leaves nothing behind.
--
-- That matters for two different reasons.
--
--   * Forensics. `venues.admins`, `currencies.minters`, and `scholars.steward`
--     are privilege-bearing columns edited through read-modify-write on an array,
--     which is lossy under concurrency and invisible afterward. If someone gains
--     admin on a venue, nothing today can say when or by whom.
--
--   * Recovery point. Without point-in-time recovery, a nightly dump means up to
--     24 hours of loss. An append-only log lets a restore replay forward from the
--     dump instead: walk rows in `seq` order and apply `after` (or delete, for a
--     DELETE). Ordering by seq naturally respects foreign-key causality, because
--     the original writes did. That is what turns "restore last night" into
--     "restore last night, then catch up".
--
-- WHAT IS AND IS NOT COVERED
--
-- Covered: the 15 mutable state tables, plus `transactions` — whose status,
-- tokens, decliner and decline_reason columns are mutable, and where auditing is
-- the only thing that records WHO approved a transaction and when. The row
-- itself only ever stores who *declined* one.
--
-- Not covered, each on purpose:
--
--   * `tokens` — token_events already covers it, in a shape roughly four times
--     smaller. Duplicating it would multiply the write cost of the highest-volume
--     table in the schema for no added information.
--   * `emails` — already an immutable log (no UPDATE or DELETE policy), and its
--     rows carry rendered message bodies. Auditing it would store every
--     notification twice.
--   * `email_verifications` — holds a sha256 token hash and a not-yet-verified
--     address. Copying a credential-like value into a second, longer-lived table
--     widens its exposure for no gain; the row is ephemeral by design.
--   * `token_events` and `audit_log` themselves — auditing an append-only log is
--     circular, and both already have their own guards.
--------------------------------------
-- Schema
create table if not exists public.audit_log (
	seq bigint generated always as identity primary key,
	-- The table the change happened to. Text rather than regclass so the log
	-- survives the table being dropped and recreated.
	tbl text not null,
	op text not null,
	-- Convenience for the common case. Null for compensation and conflicts, whose
	-- primary keys are composite — their identity is still fully present inside
	-- the before/after payloads.
	row_id uuid,
	-- The whole row, both sides. Deltas would be smaller but would make replay a
	-- merge instead of an upsert, and replay correctness matters more here than
	-- storage at this volume.
	before jsonb,
	after jsonb,
	actor uuid,
	xid xid8 not null default pg_current_xact_id (),
	at timestamptz not null default clock_timestamp()
);

alter table public.audit_log OWNER to "postgres";

-- No foreign keys, for the same reason as token_events: a log constrained by the
-- rows it describes cannot outlive them, and scholars.id cascades from
-- auth.users.
create index audit_log_tbl_seq_index on public.audit_log using btree (tbl, seq desc);

create index audit_log_row_index on public.audit_log using btree (row_id)
where
	row_id is not null;

create index audit_log_at_index on public.audit_log using btree (at);

--------------------------------------
-- Capture
create or replace function public.log_audit_event () returns trigger language plpgsql security definer
set
	search_path='' as $$
declare
	_before jsonb := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
	_after jsonb := case when tg_op = 'DELETE' then null else to_jsonb(new) end;
begin
	-- Skip writes that changed nothing. The app calls invalidateAll() after every
	-- mutation and several components re-save unchanged values, so without this
	-- the log fills with rows whose before and after are identical.
	if tg_op = 'UPDATE' and _before = _after then
		return new;
	end if;

	insert into public.audit_log (tbl, op, row_id, before, after, actor)
	values (
		tg_table_name,
		tg_op,
		-- Every covered table keys on a uuid `id` except the two composite-PK
		-- ones, where this is simply absent and resolves to null.
		nullif(coalesce(_after, _before) ->> 'id', '')::uuid,
		_before,
		_after,
		auth.uid()
	);

	if tg_op = 'DELETE' then
		return old;
	end if;
	return new;
end;
$$;

alter function public.log_audit_event () OWNER to "postgres";

-- Attached by loop rather than sixteen hand-written statements: the list is the
-- documentation, and adding a table later is a one-line change that cannot be
-- half-applied.
do $$
declare
	_t text;
	_audited text[] := array[
		'assignments', 'compensation', 'conflicts', 'currencies', 'exchanges',
		'preference_levels', 'proposals', 'roles', 'scholars', 'submission_types',
		'submissions', 'supporters', 'thanks', 'transactions', 'venues', 'volunteers'
	];
begin
	foreach _t in array _audited loop
		execute format(
			'create or replace trigger %I after insert or update or delete on public.%I
				for each row execute function public.log_audit_event()',
			_t || '_audit', _t
		);
	end loop;
end;
$$;

--------------------------------------
-- Append-only
-- A trigger, not RLS: `postgres` and `service_role` bypass policies and are
-- exactly who would be at the keyboard during an incident.
create or replace function public.audit_log_append_only () returns trigger language plpgsql
set
	search_path='' as $$
begin
	if tg_op = 'DELETE' then
		raise exception 'public.audit_log is append-only; rows are never deleted';
	end if;
	-- The one sanctioned mutation is erasure of personal data. It may rewrite the
	-- payloads and the actor — that is where names and contact emails live — but
	-- never which table changed, when, or in what order.
	if coalesce(current_setting('app.erasure', true), '') <> 'on' then
		raise exception 'public.audit_log is append-only';
	end if;
	if (new.seq, new.tbl, new.op, new.row_id, new.xid, new.at)
		is distinct from
		(old.seq, old.tbl, old.op, old.row_id, old.xid, old.at) then
		raise exception 'erasure may only rewrite before, after, and actor';
	end if;
	return new;
end;
$$;

alter function public.audit_log_append_only () OWNER to "postgres";

create or replace trigger audit_log_no_rewrite before
update
or delete on public.audit_log for each row
execute function public.audit_log_append_only ();

--------------------------------------
-- Security
alter table public.audit_log ENABLE row LEVEL SECURITY;

-- No policies, and the privileges revoked. The payloads contain whole rows,
-- including scholars' contact emails and the bodies of author thank-you notes,
-- so this is strictly more sensitive than any single table it records.
revoke all on table public.audit_log
from
	anon,
	authenticated;

-- Explicitly revoked, not merely un-granted: Supabase's default privileges give
-- service_role ALL on every new table in `public` before this file's grant runs,
-- so `grant select` alone left INSERT, UPDATE and DELETE in place and the line
-- below described a restriction that did not exist.
revoke insert,
update,
delete on table public.audit_log
from
	service_role;

grant
select
	on table public.audit_log to service_role;

-- Deliberately NOT added to supabase_realtime: it would double the change-feed
-- traffic of every audited table and trigger a second invalidateAll() per write.
--
-- Note for whoever implements erasure: a scholar's personal data reaches this
-- table inside the `before`/`after` payloads of `scholars` rows (and as `actor`
-- anywhere they acted), so forget_scholar() must scrub here as well as in
-- token_events and transactions.
