-- Replay the audit log forward over a restored database.
--
-- This is the half of the recovery-point story that the hourly tail is useless
-- without. The tail (supabase/dr/tail.sh) exports audit_log and token_events every
-- hour; this applies them, so a restore reads:
--
--     load last night's dump  ->  load the tail  ->  replay past the watermark
--
-- and the 24-hour gap between nightly backups closes to about an hour.
--
-- WHY THIS CAN BE GENERIC
--
-- audit_log stores the WHOLE row on both sides rather than a delta, which was
-- chosen precisely so replay could be an upsert rather than a merge. Applying a
-- row is therefore: delete whatever is there under its primary key, then insert
-- the `after` payload — or just the delete, for a DELETE. No per-table code.
--
-- Ordering by `seq` respects foreign-key causality for free, because the original
-- writes did: a submission cannot have been inserted before its venue.
--
-- THE CALLER MUST SUPPRESS TRIGGERS FIRST, and this refuses to run otherwise.
--
-- Replay issues ordinary INSERTs and DELETEs against a schema whose triggers are
-- live. Without `session_replication_role = replica`, every replayed row would
-- manufacture a fresh audit_log and token_events entry dated today — fabricating
-- a history in which the whole economy moved at the moment of the restore. It is
-- also what stops the transactions immutability trigger (20260808030000) from
-- rejecting historical rows for transitions that were perfectly legal when they
-- happened.
--
-- This function cannot set it for you, and the reason is worth recording: on
-- Supabase the `postgres` role is NOT a superuser (rolsuper = false). A
-- session-level `SET session_replication_role` succeeds, but the same change via
-- set_config() inside a function is refused — verified, not assumed. So the
-- requirement is checked rather than satisfied, which also keeps the suppression
-- visible in the runbook instead of hidden inside a function.
create or replace function public.replay_audit_log (
	_from_seq bigint default 0,
	_dry_run boolean default false
) returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_r record;
	_pk text[];
	_where text;
	_payload jsonb;
	_applied int := 0;
	_removed int := 0;
	_skipped int := 0;
	_last bigint := _from_seq;
begin
	if not _dry_run and current_setting('session_replication_role') <> 'replica' then
		raise exception
			'replay_audit_log requires session_replication_role = replica; run "set session_replication_role = replica;" in this session first (see RECOVERY.md)'
			using errcode = 'RR005';
	end if;

	for _r in
		select * from public.audit_log where seq > _from_seq order by seq
	loop
		-- Primary key columns for this table, in index order. Looked up per row
		-- rather than cached because a replay is rare and correctness matters more
		-- than speed; it also copes with a table whose key changed over time.
		select array_agg(a.attname order by k.ord) into _pk
		from pg_index i
		join lateral unnest(i.indkey) with ordinality as k (attnum, ord) on true
		join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
		where i.indrelid = ('public.' || _r.tbl)::regclass
			and i.indisprimary;

		if _pk is null then
			-- No primary key: nothing to match on, so applying it could duplicate
			-- rather than replace. Counted rather than guessed at.
			_skipped := _skipped + 1;
			continue;
		end if;

		_payload := coalesce(_r.after, _r.before);
		select string_agg(format('%I = %L', c, _payload ->> c), ' and ')
		into _where
		from unnest(_pk) as c;

		if not _dry_run then
			-- Delete-then-insert rather than ON CONFLICT: the conflict target would
			-- have to be built per table anyway, and this handles a row that does not
			-- exist yet identically to one that does.
			execute format('delete from public.%I where %s', _r.tbl, _where);
			if _r.op <> 'DELETE' then
				execute format(
					'insert into public.%I select * from jsonb_populate_record(null::public.%I, %L)',
					_r.tbl, _r.tbl, _r.after
				);
			end if;
		end if;

		if _r.op = 'DELETE' then _removed := _removed + 1; else _applied := _applied + 1; end if;
		_last := _r.seq;
	end loop;

	return jsonb_build_object(
		'dry_run', _dry_run,
		'from_seq', _from_seq,
		'through_seq', _last,
		'rows_applied', _applied,
		'rows_deleted', _removed,
		'rows_skipped_no_pk', _skipped
	);
end;
$$;

alter function public.replay_audit_log (bigint, boolean) OWNER to "postgres";

-- Not granted to anyone. This rewrites arbitrary rows in every audited table; it
-- is a recovery tool run deliberately by whoever holds the database, not an API.
revoke
execute on function public.replay_audit_log (bigint, boolean)
from
	public,
	anon,
	authenticated,
	service_role;
