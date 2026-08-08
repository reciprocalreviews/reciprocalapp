#!/usr/bin/env bash
#
# Capture a complete, restorable logical backup of a Supabase project.
#
# Run it from CI on a schedule, or by hand during an incident. Everything it
# writes is encrypted to an age *public* key before it leaves this machine, so
# the process that takes a backup can never read one back — a stolen CI token
# gets you the ability to write backups and nothing else.
#
#   DB_URL=postgresql://... AGE_RECIPIENT=age1... ./supabase/dr/dump.sh
#
# Environment:
#   DB_URL         required. See "the IPv6 trap" below.
#   AGE_RECIPIENT  age public key(s), whitespace- or comma-separated. Every
#                  recipient listed can decrypt the result independently, which is
#                  how the automated drill gets a key of its own without ever being
#                  handed the offline one. If unset, output is left UNENCRYPTED and
#                  the script says so loudly — only appropriate for a local drill.
#   OUT_DIR        where to write (default ./dr-out). Must not already exist.
#   PG_IMAGE       client image (default postgres:17).
#   PGSSLMODE      default `require`. Set `disable` for a local stack.
#   LABEL          free text recorded in the manifest (e.g. "nightly", "pre-migration").
#
# Why pg_dump and not `supabase db dump`:
#   `supabase db dump` is scoped to the schemas it knows about, and this database
#   is not restorable without `auth`: public.scholars.id references
#   auth.users(id) ON DELETE CASCADE, so a public-only dump restores into a
#   project with zero scholars and dangling everything. We need auth data, and we
#   need custom-format archives so a restore can be surgical (`pg_restore -t`)
#   rather than all-or-nothing.
#
# The IPv6 trap — this is the first thing that will break:
#   Supabase's *direct* database connection is IPv6-only, and GitHub-hosted
#   runners are IPv4-only. Use the SESSION-mode pooler (port 5432, host
#   aws-*.pooler.supabase.com, user postgres.<project-ref>). The TRANSACTION-mode
#   pooler on 6543 does NOT work with pg_dump.
#
# Two things live outside every schema dump and are captured separately here:
#   - cron.job, which is how `remind-daily` was silently lost once already
#     (see migration 20260517230819_restore_remind_cron.sql).
#   - vault secret NAMES. Values are deliberately never captured; they are set by
#     hand on hosted projects and belong in a password manager, not in an
#     artifact CI can write.

set -euo pipefail

DR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${DB_URL:?DB_URL is required (use the SESSION-mode pooler URI on port 5432)}"
OUT_DIR="${OUT_DIR:-dr-out}"
PG_IMAGE="${PG_IMAGE:-postgres:17}"
AGE_RECIPIENT="${AGE_RECIPIENT:-}"
PGSSLMODE="${PGSSLMODE:-require}"
LABEL="${LABEL:-manual}"
GIT_SHA="${GIT_SHA:-$(git -C "$DR_DIR" rev-parse HEAD 2>/dev/null || echo unknown)}"

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }

# Refuse to write into an existing directory: a half-populated OUT_DIR from an
# earlier failed run would otherwise be uploaded as if it were complete.
[ -e "$OUT_DIR" ] && { echo "OUT_DIR '$OUT_DIR' already exists; remove it first" >&2; exit 1; }
mkdir -p "$OUT_DIR"
OUT_ABS="$(cd "$OUT_DIR" && pwd)"

# Plaintext dumps of a PII-bearing database must never survive a failure. If we
# exit non-zero before encryption completes, take the whole directory with us.
ENCRYPTED=0
cleanup() {
	local code=$?
	if [ "$code" -ne 0 ] && [ "$ENCRYPTED" -eq 0 ]; then
		echo "!! failed before encryption completed — removing plaintext in $OUT_ABS" >&2
		rm -rf "$OUT_ABS"
	fi
}
trap cleanup EXIT

# Loopback hosts are rewritten so a containerized client can reach a stack
# running on this machine (local drills). Remote pooler URLs pass through
# untouched.
CONTAINER_URL="$(printf '%s' "$DB_URL" | sed -E 's#@(127\.0\.0\.1|localhost)([:/])#@host.docker.internal\2#')"

# Run a postgres client binary against the target. The URL travels in the
# environment, not argv, so it never shows up in `docker ps` or a process list.
# --user keeps the written files owned by the invoking user rather than root.
pgrun() {
	docker run --rm \
		--user "$(id -u):$(id -g)" \
		--add-host=host.docker.internal:host-gateway \
		-v "$OUT_ABS:/out" \
		-e PGURL="$CONTAINER_URL" \
		-e PGSSLMODE="$PGSSLMODE" \
		-e PGCONNECT_TIMEOUT=15 \
		"$PG_IMAGE" bash -c "$1"
}

say() { printf '  %s\n' "$*"; }

echo "==> Backing up (label: $LABEL)"
say "image:    $PG_IMAGE"
say "sslmode:  $PGSSLMODE"
say "out:      $OUT_ABS"

# ---------------------------------------------------------------- preflight --
SERVER_VERSION="$(pgrun 'psql "$PGURL" -X -tAc "show server_version"' | tr -d '[:space:]')"
[ -n "$SERVER_VERSION" ] || { echo "could not reach the database" >&2; exit 1; }
say "server:   PostgreSQL $SERVER_VERSION"

# pg_dump can read servers older than itself but never newer. Catch the
# upside-down case here with a clear message rather than a confusing failure
# midway through the schema dump.
CLIENT_MAJOR="$(pgrun 'pg_dump --version' | grep -oE '[0-9]+' | head -1)"
SERVER_MAJOR="${SERVER_VERSION%%.*}"
if [ "$CLIENT_MAJOR" -lt "$SERVER_MAJOR" ]; then
	echo "pg_dump $CLIENT_MAJOR cannot dump a PostgreSQL $SERVER_MAJOR server; raise PG_IMAGE" >&2
	exit 1
fi

# ------------------------------------------------------------------- dumps ---
# Application schemas, structure and data, in custom format so a restore can
# pick out a single table.
# NOT --no-privileges. That flag cost a production outage during a rehearsal: RLS
# policies and table GRANTs are different things, and dropping the grants produced
# a restore where all 71 policies were present and every row count matched, while
# PostgREST — which connects as `anon`/`authenticated` — could read nothing at all.
# The database was complete and entirely unusable, and every assertion passed.
# --no-owner stays: ownership is the platform's business, privileges are ours.
echo "==> Dumping public + private"
pgrun 'pg_dump "$PGURL" --format=custom --compress=9 --no-owner \
	--schema=public --schema=private --file=/out/public.dump'

# Auth identities, data only: the schema itself belongs to the platform and is
# recreated by provisioning a project, but the rows are ours and nothing else
# can regenerate them.
echo "==> Dumping auth.users + auth.identities"
pgrun 'pg_dump "$PGURL" --format=custom --compress=9 --no-owner --no-privileges --data-only \
	--table=auth.users --table=auth.identities --file=/out/auth.dump'

# --no-role-passwords reads pg_roles rather than pg_authid, which is what lets
# this work as a non-superuser (which is all you get on hosted Supabase).
echo "==> Dumping roles"
pgrun 'pg_dumpall --globals-only --no-role-passwords -d "$PGURL" --file=/out/roles.sql'

# ------------------------------------------------- state outside any schema --
# Extensions are cluster state, not schema state, so pg_dump emits nothing for
# them under --schema=public. That gap has already bitten once: a rehearsal
# restore dropped pg_net (created without a schema override, so it lived in
# `public`) and nothing brought it back — leaving send_email() calling a
# net.http_post that no longer existed, with mail silently never sent. That is the
# exact failure migration 20260720020000 was written to fix.
#
# chr(10) rather than E'\n' to keep this readable through two layers of shell
# quoting. pg_catalog gets no schema clause; you cannot create into it.
echo "==> Capturing extensions"
pgrun 'psql "$PGURL" -X -tAc "
	select coalesce(string_agg(
		case when n.nspname = '"'"'pg_catalog'"'"'
			then format('"'"'create extension if not exists %I;'"'"', e.extname)
			else format('"'"'create extension if not exists %I with schema %I;'"'"', e.extname, n.nspname)
		end, chr(10) order by e.extname), '"'"''"'"')
	from pg_extension e join pg_namespace n on n.oid = e.extnamespace
	where e.extname <> '"'"'plpgsql'"'"'
" > /out/extensions.sql'

echo "==> Capturing cron jobs and vault secret names"
pgrun 'psql "$PGURL" -X -tAc "
	select case when to_regclass('"'"'cron.job'"'"') is null then '"'"'[]'"'"'
		else coalesce((select jsonb_pretty(jsonb_agg(to_jsonb(j))) from cron.job j), '"'"'[]'"'"') end
" > /out/cron.json'

# ---------------------------------------------------------------- manifest ---
echo "==> Building manifest"
cp "$DR_DIR/manifest.sql" "$OUT_ABS/.manifest.sql"
pgrun 'psql "$PGURL" -X -tA -f /out/.manifest.sql > /out/.db.json'
rm -f "$OUT_ABS/.manifest.sql"

# Checksums are what turn a drill into an assertion: verify these before
# decrypting anything, and a truncated or tampered upload is caught immediately.
checksums_json() {
	local first=1
	printf '{'
	for f in "$OUT_ABS"/*; do
		local base; base="$(basename "$f")"
		case "$base" in .*) continue ;; esac
		[ "$first" -eq 1 ] || printf ','
		first=0
		printf '"%s":"%s"' "$base" "$(sha256sum "$f" | cut -d' ' -f1)"
	done
	printf '}'
}

# Assembled with printf rather than jq so this script keeps working on a laptop
# during an incident. The two embedded fragments are JSON produced by psql.
cat > "$OUT_ABS/manifest.json" <<EOF
{
  "taken_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "label": "$LABEL",
  "git_sha": "$GIT_SHA",
  "pg_client_major": $CLIENT_MAJOR,
  "encrypted": $([ -n "$AGE_RECIPIENT" ] && echo true || echo false),
  "sha256": $(checksums_json),
  "db": $(cat "$OUT_ABS/.db.json")
}
EOF
rm -f "$OUT_ABS/.db.json"

# ---------------------------------------------------------------- encrypt ----
if [ -z "$AGE_RECIPIENT" ]; then
	cat >&2 <<-'WARN'

	!! AGE_RECIPIENT is unset, so this backup is UNENCRYPTED PLAINTEXT.
	!! It contains contact emails, ORCID iDs, real names, and the full
	!! transaction history. Acceptable for a local drill; never upload it.

	WARN
	ENCRYPTED=1
else
	# One -r per recipient. age encrypts the file once and wraps the key for each,
	# so a second recipient costs a few dozen bytes rather than a second copy.
	AGE_ARGS=""
	for _r in $(printf '%s' "$AGE_RECIPIENT" | tr ',' ' '); do
		AGE_ARGS="$AGE_ARGS -r $_r"
	done
	echo "==> Encrypting to $(printf '%s' "$AGE_RECIPIENT" | tr ',' ' ' | wc -w | tr -d ' ') recipient(s)"
	# age is the one non-Postgres dependency. Prefer a local binary, and
	# otherwise borrow one from a throwaway container, so this script still runs
	# during an incident on a machine that has nothing installed but Docker. One
	# container encrypts every file rather than one per file.
	if command -v age >/dev/null 2>&1; then
		for f in "$OUT_ABS"/*; do
			case "$f" in *.age) continue ;; esac
			age $AGE_ARGS -o "$f.age" "$f" && rm -f "$f"
		done
	else
		say "(no local age binary; borrowing one from a container)"
		# This container runs as root, unlike the postgres ones above, because apk
		# needs root to install. It therefore has to hand the files back: without
		# the trailing chown the encrypted output would be root-owned and the
		# invoking user could not upload or clean it up. (On Docker Desktop the
		# chown is a harmless no-op; on Linux it is essential.)
		docker run --rm \
			-v "$OUT_ABS:/out" \
			-e AGE_ARGS="$AGE_ARGS" \
			-e UIDGID="$(id -u):$(id -g)" \
			alpine:3 sh -c '
				set -e
				apk add --no-cache age >/dev/null
				for f in /out/*; do
					case "$f" in *.age) continue ;; esac
					age $AGE_ARGS -o "$f.age" "$f"
					rm -f "$f"
				done
				chown -R "$UIDGID" /out'
	fi
	ENCRYPTED=1
fi

echo "==> Done"
ls -lh "$OUT_ABS" | tail -n +2 | awk '{printf "  %-24s %s\n", $9, $5}'
