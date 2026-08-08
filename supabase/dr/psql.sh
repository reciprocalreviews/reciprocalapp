#!/usr/bin/env bash
#
# Run psql against any database without installing Postgres locally.
#
# Every other script in this directory reaches the database through a container
# already; this exposes the same thing for the manual steps in RECOVERY.md, so a
# recovery never stalls on "psql: command not found" — which is a bad sentence to
# read during an incident.
#
#   DB_URL=postgresql://... ./supabase/dr/psql.sh -c "select 1"
#   DB_URL=postgresql://... ./supabase/dr/psql.sh -f supabase/dr/quarantine.sql
#   DB_URL=postgresql://... ./supabase/dr/psql.sh            # interactive shell
#
# Any argument psql accepts works. Files are resolved relative to the repository
# root and mounted read-only, so -f works on the scripts in this directory.
#
# Note for hosted targets: PGSSLMODE defaults to `require`. Set it to `disable`
# for a local stack.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${DB_URL:?DB_URL is required (session-mode pooler URI for a hosted project)}"
PG_IMAGE="${PG_IMAGE:-postgres:17}"
PGSSLMODE="${PGSSLMODE:-require}"

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }

# Loopback hosts are rewritten so the container can reach a stack on this
# machine; remote pooler URLs pass through untouched.
CONTAINER_URL="$(printf '%s' "$DB_URL" | sed -E 's#@(127\.0\.0\.1|localhost)([:/])#@host.docker.internal\2#')"

# -it only when attached to a terminal, so this stays usable in a pipeline.
# Written as a plain string rather than an array: macOS ships bash 3.2, where
# expanding an empty array under `set -u` is an error.
TTY=""
if [ -t 0 ] && [ -t 1 ]; then TTY="-it"; fi

exec docker run --rm $TTY \
	--add-host=host.docker.internal:host-gateway \
	-v "$REPO:/repo:ro" \
	--workdir /repo \
	-e PGURL="$CONTAINER_URL" \
	-e PGSSLMODE="$PGSSLMODE" \
	-e PGCONNECT_TIMEOUT=15 \
	"$PG_IMAGE" \
	psql "$CONTAINER_URL" "$@"
