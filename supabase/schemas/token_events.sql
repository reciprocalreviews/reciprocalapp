-- An append-only log of every change of token ownership.
--
-- WHY THIS EXISTS
--
-- `public.tokens` is the state table: one row per token, and a transfer is an
-- in-place UPDATE of its scholar/venue columns. It has no created_at, no
-- history, and no versioning, so once ownership is overwritten the previous
-- owner is gone from the database entirely. Balances are `count(*)` over that
-- table, which means the current balance is the *only* thing the schema knows.
--
-- `public.transactions` looks like it should fill that gap, and it does not.
-- Nothing derives from it and it derives from nothing: it has no amount column
-- (the amount is cardinality(tokens)), its `tokens` array is rewritten from
-- placeholder UUIDs to real ids on approval, and it records an assertion about
-- who paid rather than an observation of what moved. It is a narrative, kept in
-- step with reality only by convention inside the SECURITY DEFINER RPCs.
--
-- This table is the observation. With it, token state at any past instant is
-- reconstructible (see tokens_as_of below), which turns "we discovered on
-- Thursday that Tuesday's deploy corrupted balances" from a full restore that
-- discards two days of legitimate work into a diff and a targeted repair.
--
-- WHY A TRIGGER RATHER THAN LOGGING INSIDE THE RPCs
--
-- A trigger sits below RLS and below the RPC boundary, so it captures every
-- path: the RPCs, a direct PostgREST write, a service_role script, manual psql
-- surgery during an incident, and a restore. Logging inside the RPCs would
-- require believing that every write goes through them — which is exactly the
-- belief that turned out to be false when `tokens` was found to be directly
-- writable from the browser (fixed in 20260802010000). Completeness by
-- construction is the entire point.
--------------------------------------
-- Schema
create type public.token_op as enum('mint', 'move', 'burn');

alter type public.token_op OWNER to "postgres";

create table if not exists public.token_events (
	-- Insertion order, and the only monotonic column this schema has besides
	-- transactions.seq. See the caveat on commit order at the bottom.
	seq bigint generated always as identity primary key,
	-- The token whose ownership changed.
	token uuid not null,
	op public.token_op not null,
	-- Ownership AFTER the event.
	currency uuid not null,
	scholar uuid,
	venue uuid,
	-- Ownership BEFORE. Both null for a mint. Redundant with the previous event
	-- for this token, which is deliberate: it makes a single row self-describing
	-- and makes gap detection possible, because event N's prev_* must equal event
	-- N-1's owner. A break in that chain means a write escaped the trigger, or a
	-- partial restore landed.
	prev_scholar uuid,
	prev_venue uuid,
	-- The transaction this movement belongs to, set by the RPCs through the
	-- app.txn GUC. A 'move' with a null txn is an unattributed movement of value:
	-- the corruption alarm. (Attribution arrives in the next migration; every row
	-- written before then legitimately has a null txn.)
	txn uuid,
	-- auth.uid() at the time, when there was one.
	actor uuid,
	-- Groups every row written by one database transaction: a 500-token mint is
	-- 500 rows sharing one xid.
	xid xid8 not null default pg_current_xact_id (),
	at timestamptz not null default clock_timestamp()
);

alter table public.token_events OWNER to "postgres";

-- Deliberately NO foreign keys to tokens, scholars, venues, or transactions.
-- A log constrained by the rows it describes cannot outlive them, and
-- scholars.id cascades from auth.users — so an accidental account deletion would
-- silently delete the evidence of it. FK-free is what lets this table survive a
-- cascade and what lets the reconciler *detect* one.
--------------------------------------
-- Indexes
-- "What happened to this token, most recent first" — the reconstruction query.
create index token_events_token_seq_index on public.token_events using btree (token, seq desc);

-- "Which movements belong to this transaction" — reconciliation joins.
create index token_events_txn_index on public.token_events using btree (txn)
where
	txn is not null;

-- tokens_as_of() and any time-bounded forensics.
create index token_events_at_index on public.token_events using btree (at);

-- The corruption alarm, kept cheap: this index contains only unattributed rows,
-- so in a healthy system it is empty and the check is close to free.
create index token_events_unattributed_index on public.token_events using btree (seq)
where
	txn is null;

--------------------------------------
-- Capture
create or replace function public.log_token_event () returns trigger language plpgsql security definer
set
	search_path='' as $$
declare
	_txn uuid := nullif(current_setting('app.txn', true), '')::uuid;
	_actor uuid := auth.uid();
begin
	if tg_op = 'INSERT' then
		insert into public.token_events (token, op, currency, scholar, venue, prev_scholar, prev_venue, txn, actor)
		values (new.id, 'mint', new.currency, new.scholar, new.venue, null, null, _txn, _actor);
		return new;
	elsif tg_op = 'DELETE' then
		-- Unreachable today: the DELETE policy denies everyone and the privilege
		-- is revoked. Handled anyway so that if a token is ever destroyed — by a
		-- future migration, or by the owner during an incident — the log says so
		-- rather than simply ending.
		insert into public.token_events (token, op, currency, scholar, venue, prev_scholar, prev_venue, txn, actor)
		values (old.id, 'burn', old.currency, null, null, old.scholar, old.venue, _txn, _actor);
		return old;
	else
		insert into public.token_events (token, op, currency, scholar, venue, prev_scholar, prev_venue, txn, actor)
		values (new.id, 'move', new.currency, new.scholar, new.venue, old.scholar, old.venue, _txn, _actor);
		return new;
	end if;
end;
$$;

alter function public.log_token_event () OWNER to "postgres";

-- Two triggers rather than one: a WHEN clause cannot reference OLD on INSERT, so
-- the ownership-changed guard can only be attached to the UPDATE.
create or replace trigger tokens_event_log_write
after insert
or delete on public.tokens for each row
execute function public.log_token_event ();

create or replace trigger tokens_event_log_move
after
update of scholar,
venue,
currency on public.tokens for each row when (
	(old.scholar, old.venue, old.currency) is distinct from (new.scholar, new.venue, new.currency)
)
execute function public.log_token_event ();

--------------------------------------
-- Append-only
-- RLS alone cannot enforce this: `postgres` and `service_role` bypass policies,
-- and they are exactly who would be at the keyboard during an incident. A
-- trigger applies to everyone.
create or replace function public.token_events_append_only () returns trigger language plpgsql
set
	search_path='' as $$
begin
	if tg_op = 'DELETE' then
		raise exception 'public.token_events is append-only; rows are never deleted';
	end if;
	-- The single sanctioned mutation is erasure of personal data, which nulls the
	-- subject columns and leaves the movement itself intact. It must announce
	-- itself by setting app.erasure, so an accidental UPDATE still fails.
	if coalesce(current_setting('app.erasure', true), '') <> 'on' then
		raise exception 'public.token_events is append-only';
	end if;
	if (new.seq, new.token, new.op, new.currency, new.venue, new.prev_venue, new.txn, new.xid, new.at)
		is distinct from
		(old.seq, old.token, old.op, old.currency, old.venue, old.prev_venue, old.txn, old.xid, old.at)
		or new.scholar is not null
		or new.prev_scholar is not null
		or new.actor is not null then
		raise exception 'erasure may only null scholar, prev_scholar, and actor';
	end if;
	return new;
end;
$$;

alter function public.token_events_append_only () OWNER to "postgres";

create or replace trigger token_events_no_rewrite before
update
or delete on public.token_events for each row
execute function public.token_events_append_only ();

--------------------------------------
-- Security
alter table public.token_events ENABLE row LEVEL SECURITY;

-- No policies at all, so `authenticated` and `anon` see nothing. Historical token
-- ownership is not currently visible to scholars anywhere in the product, and
-- exposing it would leak reviewing activity that venue anonymity settings are
-- meant to protect. Kept closed until there is a reason to open it.
revoke all on table public.token_events
from
	anon,
	authenticated;

-- Explicitly revoked, not merely un-granted: Supabase's default privileges give
-- service_role ALL on every new table in `public` before this file's grant runs,
-- so `grant select` alone left INSERT, UPDATE and DELETE in place and the line
-- below described a restriction that did not exist.
revoke insert,
update,
delete on table public.token_events
from
	service_role;

grant
select
	on table public.token_events to service_role;

-- Deliberately NOT added to supabase_realtime. A 500-token mint would fan 500
-- rows out to every connected client, each firing invalidateAll().
--------------------------------------
-- Reconstruction
-- Token ownership as it stood at a given instant. Diff this against `tokens` to
-- find exactly what a bug changed, and repair only the difference — no restore,
-- and no loss of the legitimate work that happened in between.
--
-- MIND THE CLOCK. `token_events.at` is clock_timestamp(), which advances during a
-- transaction, because collapsing every event of one RPC onto a single instant is
-- exactly the flaw that makes transactions.created_at useless for ordering.
-- `now()`, by contrast, is transaction START time. So calling
-- `tokens_as_of(now())` from inside the same transaction that just wrote events
-- silently omits them — it asks for a moment that predates your own work. Hence
-- the default: `tokens_as_of()` always means "as of right now, really now".
-- Passing an explicit timestamp is for looking at the past, which is the point.
create or replace function public.tokens_as_of (_at timestamptz default clock_timestamp()) returns table (
	token uuid,
	currency uuid,
	scholar uuid,
	venue uuid
) language sql stable security definer
set
	search_path='' as $$
	select distinct on (e.token) e.token, e.currency, e.scholar, e.venue
	from public.token_events e
	where e.at <= _at
	order by e.token, e.seq desc;
$$;

alter function public.tokens_as_of (timestamptz) OWNER to "postgres";

revoke
execute on function public.tokens_as_of (timestamptz)
from
	public;

grant
execute on function public.tokens_as_of (timestamptz) to service_role;

-- Caveat, recorded here because it will matter to whoever writes the replay
-- tooling: an identity column gives INSERTION order, not COMMIT order. Under
-- concurrency a row with a lower seq can become visible after one with a higher
-- seq. At this write volume it never matters, but anything treating seq as a
-- replication watermark should compare against
-- pg_snapshot_xmin(pg_current_snapshot()) rather than assuming max(seq) is final.
