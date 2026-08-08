#!/usr/bin/env bash
#
# Export the append-only logs written since a cutoff — the "tail" that closes the
# gap between nightly backups.
#
#   DB_URL=postgresql://... AGE_RECIPIENT=age1... ./supabase/dr/tail.sh
#
# WHY THIS IS SMALL ENOUGH TO RUN HOURLY
#
# A full dump every hour would be wasteful and slow. But the recovery gap is not
# about re-copying the whole database — it is about the changes since the last
# copy, and every one of those is already recorded in two append-only tables:
#
#   token_events  every change of token ownership
#   audit_log     every insert, update and delete across the 16 mutable tables,
#                 with the whole row on both sides
#
# Replaying those forward over last night's dump reconstructs the database, so an
# hourly export of a few kilobytes buys the same recovery point that an hourly
# full backup would.
#
# WHAT IS DELIBERATELY NOT HERE
#
#   `emails`  — append-only, but re-inserting its rows RE-SENDS them: the
#               send_on_email_insert trigger posts every row to the edge function.
#               A tail that mails your users on replay is worse than a lost hour
#               of send records.
#   `tokens`, `transactions`, and the other mutable tables — reconstructed by
#               replaying token_events and audit_log, so copying them too would
#               be redundant and would reintroduce the ordering problem the logs
#               exist to solve.
#
# AUTH IS INCLUDED, because it has to be. A scholar who signed up in the last
# hour has a `scholars` row inside audit_log and an `auth.users` row nowhere —
# and scholars.id references auth.users(id), so replaying without it fails on the
# foreign key.
#
# THE WINDOW OVERLAPS ON PURPOSE. Scheduled GitHub workflows can run 20–30 minutes
# late under load, so an exactly-one-hour window would leave holes. Three hours at
# an hourly cadence means two consecutive misses are still covered, and replay
# deduplicates on `seq`.

set -euo pipefail

: "${DB_URL:?DB_URL is required (session-mode pooler URI on port 5432)}"
OUT_DIR="${OUT_DIR:-dr-tail}"
PG_IMAGE="${PG_IMAGE:-postgres:17}"
AGE_RECIPIENT="${AGE_RECIPIENT:-}"
PGSSLMODE="${PGSSLMODE:-require}"
WINDOW_HOURS="${WINDOW_HOURS:-3}"

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
[ -e "$OUT_DIR" ] && { echo "OUT_DIR '$OUT_DIR' already exists; remove it first" >&2; exit 1; }
mkdir -p "$OUT_DIR"
OUT_ABS="$(cd "$OUT_DIR" && pwd)"

ENCRYPTED=0
cleanup() {
	local code=$?
	if [ "$code" -ne 0 ] && [ "$ENCRYPTED" -eq 0 ]; then
		echo "!! failed before encryption completed — removing plaintext in $OUT_ABS" >&2
		rm -rf "$OUT_ABS"
	fi
}
trap cleanup EXIT

CONTAINER_URL="$(printf '%s' "$DB_URL" | sed -E 's#@(127\.0\.0\.1|localhost)([:/])#@host.docker.internal\2#')"

pgrun() {
	docker run --rm --user "$(id -u):$(id -g)" \
		--add-host=host.docker.internal:host-gateway \
		-v "$OUT_ABS:/out" -e PGURL="$CONTAINER_URL" -e PGSSLMODE="$PGSSLMODE" \
		-e PGCONNECT_TIMEOUT=15 -e W="$WINDOW_HOURS" \
		"$PG_IMAGE" bash -c "$1"
}
say() { printf '  %s\n' "$*"; }

echo "==> Tailing the last ${WINDOW_HOURS}h"

# The cutoff is built once, here, and interpolated as a literal. An earlier
# version passed WINDOW_HOURS into the container and referenced it inside the
# quoted SQL, where it was expanded by the OUTER shell instead — three layers of
# quoting hiding a plain bug. WINDOW_HOURS is our own integer, so interpolating
# it is safe as well as legible.
CUT="now() - interval '${WINDOW_HOURS} hours'"

# `at` is clock_timestamp() on both log tables — real wall-clock — so comparing it
# against now() from this separate transaction is sound. CSV with a header so a
# replay can \copy it straight back and a human can read it.
copy_out() { # copy_out <select> <file>
	pgrun "psql \"\$PGURL\" -X -q -c \"\\copy ($1) to /out/$2 (format csv, header)\""
}

copy_out "select * from public.token_events where at >= $CUT order by seq" token_events.csv
copy_out "select * from public.audit_log where at >= $CUT order by seq" audit_log.csv
copy_out "select * from auth.users where created_at >= $CUT" auth_users.csv
copy_out "select * from auth.identities where created_at >= $CUT" auth_identities.csv

# The watermarks a replay stops at, and the counts to check it against.
pgrun "psql \"\$PGURL\" -X -tAc \"
select jsonb_pretty(jsonb_build_object(
	'taken_at', to_char(now() at time zone 'utc', 'YYYY-MM-DD\\\"T\\\"HH24:MI:SS\\\"Z\\\"'),
	'window_hours', ${WINDOW_HOURS},
	'max_seq', jsonb_build_object(
		'token_events', (select coalesce(max(seq),0) from public.token_events),
		'audit_log', (select coalesce(max(seq),0) from public.audit_log),
		'transactions', (select coalesce(max(seq),0) from public.transactions)
	)
))\" > /out/tail.json"

for f in "$OUT_ABS"/*.csv; do
	printf '  %-22s %s rows\n' "$(basename "$f")" "$(( $(wc -l < "$f") - 1 ))"
done
say "watermarks: $(tr -d ' \n' < "$OUT_ABS/tail.json" | sed 's/.*"max_seq"://;s/}}$/}/')"

if [ -z "$AGE_RECIPIENT" ]; then
	echo "!! AGE_RECIPIENT unset — output is PLAINTEXT. Local drills only." >&2
	ENCRYPTED=1
else
	AGE_ARGS=""
	for _r in $(printf '%s' "$AGE_RECIPIENT" | tr ',' ' '); do AGE_ARGS="$AGE_ARGS -r $_r"; done
	if command -v age >/dev/null 2>&1; then
		for f in "$OUT_ABS"/*; do
			case "$f" in *.age) continue ;; esac
			age $AGE_ARGS -o "$f.age" "$f" && rm -f "$f"
		done
	else
		docker run --rm -v "$OUT_ABS:/out" -e AGE_ARGS="$AGE_ARGS" -e UIDGID="$(id -u):$(id -g)" alpine:3 sh -c '
			set -e; apk add --no-cache age >/dev/null
			for f in /out/*; do case "$f" in *.age) continue ;; esac; age $AGE_ARGS -o "$f.age" "$f"; rm -f "$f"; done
			chown -R "$UIDGID" /out'
	fi
	ENCRYPTED=1
	say "encrypted"
fi
