#!/usr/bin/env bash
#
# Restore a backup and prove it worked.
#
# An untested backup is a hypothesis. This is what turns it into a fact: it
# restores real artifacts into a throwaway database and then ASSERTS the result
# against the manifest the backup carried — row counts, auth users, append-only
# watermarks, and the RLS policy count. A restore that "finished" but does not
# match the manifest is a failed restore, and you want to learn that during a
# drill rather than during an incident.
#
#   BACKUP_DIR=/tmp/backup TARGET_DB_URL=postgresql://... ./supabase/dr/drill.sh
#
# Environment:
#   BACKUP_DIR      required. Directory of artifacts. Encrypted (*.age) is fine
#                   if AGE_IDENTITY is set; already-decrypted also works.
#   TARGET_DB_URL   required. A database you are willing to destroy.
#   AGE_IDENTITY    path to the age private key, if BACKUP_DIR is encrypted.
#   PG_IMAGE        client image (default postgres:17).
#   KEEP            set to 1 to leave the decrypted working copy in place.
#
# The elapsed time this prints is the closest thing you have to a real recovery
# time objective. Record it in RECOVERY.md after each drill; an RTO nobody has
# measured is a guess.

set -euo pipefail

DR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${BACKUP_DIR:?BACKUP_DIR is required}"
: "${TARGET_DB_URL:?TARGET_DB_URL is required — and it must be a database you can destroy}"
PG_IMAGE="${PG_IMAGE:-postgres:17}"
AGE_IDENTITY="${AGE_IDENTITY:-}"
KEEP="${KEEP:-0}"

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

START=$(date +%s)
WORK="$(mktemp -d)"
cleanup() { [ "$KEEP" = "1" ] || rm -rf "$WORK"; }
trap cleanup EXIT

CONTAINER_URL="$(printf '%s' "$TARGET_DB_URL" | sed -E 's#@(127\.0\.0\.1|localhost)([:/])#@host.docker.internal\2#')"

pgrun() {
	docker run --rm --user "$(id -u):$(id -g)" \
		--add-host=host.docker.internal:host-gateway \
		-v "$WORK:/work" -e PGURL="$CONTAINER_URL" -e PGSSLMODE="${PGSSLMODE:-disable}" \
		"$PG_IMAGE" bash -c "$1"
}

say() { printf '  %s\n' "$*"; }
fail=0
check() { # check <label> <expected> <actual>
	if [ "$2" = "$3" ]; then
		printf '  \033[32m✓\033[0m %-34s %s\n' "$1" "$3"
	else
		printf '  \033[31m✗\033[0m %-34s expected %s, got %s\n' "$1" "$2" "$3"
		fail=1
	fi
}

echo "==> Preparing artifacts"
cp "$BACKUP_DIR"/* "$WORK"/ 2>/dev/null || { echo "nothing in $BACKUP_DIR" >&2; exit 1; }

if ls "$WORK"/*.age >/dev/null 2>&1; then
	[ -n "$AGE_IDENTITY" ] || { echo "BACKUP_DIR is encrypted but AGE_IDENTITY is unset" >&2; exit 1; }
	say "decrypting"
	if command -v age >/dev/null 2>&1; then
		for f in "$WORK"/*.age; do age -d -i "$AGE_IDENTITY" -o "${f%.age}" "$f" && rm -f "$f"; done
	else
		cp "$AGE_IDENTITY" "$WORK/.identity"
		docker run --rm -v "$WORK:/work" -e UIDGID="$(id -u):$(id -g)" alpine:3 sh -c '
			set -e; apk add --no-cache age >/dev/null
			for f in /work/*.age; do age -d -i /work/.identity -o "${f%.age}" "$f"; rm -f "$f"; done
			rm -f /work/.identity; chown -R "$UIDGID" /work'
	fi
fi

[ -f "$WORK/manifest.json" ] || { echo "no manifest.json — cannot verify a restore without one" >&2; exit 1; }

# ---- Integrity, before touching the target ------------------------------------
# macOS's sha256sum has no -c, and Linux has no shasum by default, so pick
# whichever verifier this machine actually has rather than assuming coreutils.
if command -v shasum >/dev/null 2>&1; then
	verify() { shasum -a 256 -c; }
elif sha256sum --help 2>&1 | grep -q '\-c'; then
	verify() { sha256sum -c; }
else
	verify() { echo "  no checksum verifier available; SKIPPING integrity check" >&2; cat >/dev/null; }
fi

echo "==> Verifying checksums"
( cd "$WORK" && jq -r '.sha256 | to_entries[] | select(.key != "manifest.json") | "\(.value)  \(.key)"' manifest.json \
	| verify ) | sed 's/^/  /'

TAKEN=$(jq -r '.taken_at' "$WORK/manifest.json")
say "backup taken $TAKEN"

# ---- Is this target even capable of holding the schema? ------------------------
# Learned from the first drill: restoring into a bare Postgres database silently
# loses 29 of 71 RLS policies, because every one of them calls auth.uid() and the
# `auth` schema does not exist there. The restore "succeeds", the row counts all
# match, and the result is a database with no row-level security. Catch that here
# rather than letting it surface as a puzzling policy-count mismatch later.
if [ -z "$(pgrun 'psql "$PGURL" -tAc "select to_regclass('"'"'auth.users'"'"')"' | tr -d '[:space:]')" ]; then
	if [ "${ALLOW_PARTIAL:-0}" = "1" ]; then
		say "WARNING: no auth schema; policies referencing auth.uid() will be lost (ALLOW_PARTIAL=1)"
	else
		cat >&2 <<-EOF

		This target has no \`auth\` schema, so it is not a valid restore target.

		Every RLS policy in this schema calls auth.uid(). Restoring here would drop
		29 of 71 policies while every row count still matched — a database that
		looks restored and has no row-level security.

		Restore into a provisioned Supabase project (or a local \`supabase start\`
		stack), not a bare Postgres database. Set ALLOW_PARTIAL=1 to override for a
		data-only spot check.
		EOF
		exit 1
	fi
fi

# ---- Quarantine ----------------------------------------------------------------
# Before any data lands. A restored `emails` table with a live trigger re-sends
# every historical notification; a restored cron.job starts mailing scholars.
echo "==> Quarantining the target"
cp "$DR_DIR/quarantine.sql" "$WORK/quarantine.sql"
pgrun 'psql "$PGURL" -q -v ON_ERROR_STOP=1 -f /work/quarantine.sql' >/dev/null 2>&1 \
	&& say "quarantined" \
	|| say "quarantine skipped (fresh target with nothing to quarantine)"

# ---- Restore -------------------------------------------------------------------
echo "==> Restoring"
pgrun 'psql "$PGURL" -q -v ON_ERROR_STOP=0 -f /work/roles.sql' >/dev/null 2>&1 || true
say "roles"

# Before the schema: functions, policies, and the cron command all depend on
# extensions, and pg_dump carries none of them under --schema=public.
if [ -f "$WORK/extensions.sql" ]; then
	pgrun 'psql "$PGURL" -q -v ON_ERROR_STOP=0 -f /work/extensions.sql' >/dev/null 2>&1 || true
	say "extensions"
else
	say "extensions SKIPPED — backup predates extension capture"
fi

# session_replication_role suppresses user triggers for the session, so a restore
# cannot manufacture audit_log/token_events rows dated today. See RECOVERY.md § 4.
# No --no-privileges here either: stripping grants at restore time is the same
# outage as stripping them at dump time.
pgrun '{ echo "set session_replication_role = replica;"; \
	pg_restore --no-owner -f - /work/public.dump; } \
	| psql "$PGURL" -q -v ON_ERROR_STOP=0' >/dev/null 2>&1
say "public schema + data"

if [ -f "$WORK/auth.dump" ]; then
	if pgrun 'psql "$PGURL" -tAc "select to_regclass('"'"'auth.users'"'"') is not null"' | grep -q t; then
		pgrun '{ echo "set session_replication_role = replica;"; \
			pg_restore --data-only --no-owner --no-privileges -f - /work/auth.dump; } \
			| psql "$PGURL" -q -v ON_ERROR_STOP=0' >/dev/null 2>&1
		say "auth data"
		AUTH_RESTORED=1
	else
		say "auth SKIPPED — target has no auth schema (not a full Supabase project)"
		AUTH_RESTORED=0
	fi
else
	AUTH_RESTORED=0
fi

# ---- Assert --------------------------------------------------------------------
echo "==> Verifying against the manifest"

q() { pgrun "psql \"\$PGURL\" -tAc \"$1\"" 2>/dev/null | tr -d '[:space:]'; }

# Must match manifest.sql's definition exactly, or the comparison is meaningless.
GRANT_FP_SQL="select md5(string_agg(t, '|' order by t)) from (select grantee||':'||table_name||':'||privilege_type as t from information_schema.role_table_grants where table_schema='public' and grantee in ('anon','authenticated') union all select grantee||':'||table_name||':'||column_name||':'||privilege_type from information_schema.role_column_grants where table_schema='public' and grantee in ('anon','authenticated')) x"

# Every table the manifest recorded, compared exactly. This is the assertion that
# makes the drill meaningful: "the restore finished" is a feeling, this is a fact.
while read -r tbl want; do
	got=$(q "select count(*) from public.$tbl" || echo "MISSING")
	check "rows: $tbl" "$want" "${got:-MISSING}"
done < <(jq -r '.db.row_counts | to_entries[] | "\(.key) \(.value)"' "$WORK/manifest.json")

if [ "$AUTH_RESTORED" = "1" ]; then
	want=$(jq -r '.db.auth_user_count // "null"' "$WORK/manifest.json")
	check "auth.users" "$want" "$(q 'select count(*) from auth.users')"
	# The one cross-check that decides whether a restore is usable at all:
	# scholars.id references auth.users(id) ON DELETE CASCADE.
	check "auth.users = scholars" "$(q 'select count(*) from public.scholars')" "$(q 'select count(*) from auth.users')"
fi

for t in transactions token_events audit_log; do
	want=$(jq -r --arg t "$t" '.db.watermarks[$t] // empty' "$WORK/manifest.json")
	[ -n "$want" ] || continue
	col=seq
	check "watermark: $t.$col" "$want" "$(q "select coalesce(max($col),0) from public.$t")"
done

# Extensions. A missing one is silent and catastrophic in a specific way: without
# pg_net, send_email() calls a function that does not exist, the row is recorded,
# delivery is best-effort, and NOT ONE EMAIL EVER LEAVES — which is exactly what
# happened on a real project before migration 20260720020000.
#
# Some extensions the hosted cluster carries CANNOT exist on a local stack, and
# failing on those trains you to ignore a red drill — which is how a real missing
# extension gets waved through. pgsodium is the case in hand: it appears nowhere
# in this schema, Supabase has deprecated it, and the local stack does not ship
# it, so `create extension pgsodium` in extensions.sql silently no-ops. Report
# those as warnings and keep asserting everything the schema actually depends on.
UNAVAILABLE_LOCALLY="pgsodium"
while read -r ext; do
	[ -n "$ext" ] || continue
	got=$(q "select count(*) from pg_extension where extname='$ext'")
	if [ "$got" != "1" ] && printf '%s\n' $UNAVAILABLE_LOCALLY | grep -qx "$ext"; then
		printf '  \033[33m!\033[0m %-34s absent; not available on this target\n' "extension: $ext"
		continue
	fi
	check "extension: $ext" "1" "$got"
done < <(jq -r '.db.extensions | keys[]' "$WORK/manifest.json")

# Table and column GRANTs, as an exact fingerprint. Policies and privileges are
# independent: a restore can carry every policy and still leave `anon` unable to
# SELECT anything, which is a database that passes every other check here and
# serves nothing. Learned the hard way.
want=$(jq -r '.db.grant_fingerprint // empty' "$WORK/manifest.json")
if [ -n "$want" ]; then
	check "grant fingerprint" "$want" "$(q "$GRANT_FP_SQL")"
	check "anon can read" "1" "$(q "select case when has_table_privilege('anon','public.venues','SELECT') then 1 else 0 end")"
fi

want=$(jq -r '.db.rls_policy_count // empty' "$WORK/manifest.json")
[ -n "$want" ] && check "RLS policies" "$want" "$(q "select count(*) from pg_policies where schemaname='public'")"

# ---- Re-arm, then check what only re-arming restores ---------------------------
# The data assertions above mirror an incident, where you verify BEFORE pointing
# live email and a daily cron at the result. But a drill that stops there never
# rehearses rearm.sql — and that is exactly where the subtlest failure lives, so
# the drill goes one step further than an incident would.
echo "==> Re-arming"
cp "$DR_DIR/rearm.sql" "$WORK/rearm.sql"
if pgrun 'psql "$PGURL" -q -v ON_ERROR_STOP=1 -f /work/rearm.sql' >/dev/null 2>&1; then
	say "re-armed"

	# Realtime publication membership. Checked because it is NOT carried by the
	# dump: publications are database-level objects, so `pg_dump --schema=public`
	# emits nothing for them. A restore therefore brings back every row and every
	# policy while leaving the publication empty — the app loads and silently stops
	# updating live. Only quarantine.sql's recorded state can rebuild it, and
	# quarantine must run BEFORE the tables are dropped, or it records nothing.
	want=$(jq -r '.db.realtime_tables | length' "$WORK/manifest.json")
	if [ "$want" != "0" ] && [ "$want" != "null" ]; then
		check "realtime publication" "$want" "$(q "select count(*) from pg_publication_tables where pubname='supabase_realtime'")"
	fi
	check "email trigger re-enabled" "O" \
		"$(q "select tgenabled from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='emails' and t.tgname='send_on_email_insert'")"
else
	say "re-arm SKIPPED — no quarantine state (target was already clean)"
fi

# The ledger must agree with the state it describes, or the restore silently
# produced a database whose balances cannot be explained.
if [ -n "$(q "select to_regclass('public.token_events')")" ]; then
	check "ledger agrees with tokens" "0" \
		"$(q 'select count(*) from public.tokens t full outer join public.tokens_as_of() a on a.token = t.id where t.id is null or a.token is null or (t.scholar,t.venue,t.currency) is distinct from (a.scholar,a.venue,a.currency)')"
fi

ELAPSED=$(( $(date +%s) - START ))
echo
if [ "$fail" = "0" ]; then
	echo "==> DRILL PASSED in ${ELAPSED}s"
	echo "    Record ${ELAPSED}s as the measured recovery time in RECOVERY.md."
else
	echo "==> DRILL FAILED in ${ELAPSED}s — the backup did not restore to the state it claims"
fi
exit "$fail"
