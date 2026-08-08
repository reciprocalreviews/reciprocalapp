#!/usr/bin/env bash
#
# Apply an hourly tail to a freshly restored database, closing the gap between the
# nightly dump and the moment of the failure.
#
#   TAIL_DIR=/tmp/tail FROM_SEQ=63 TARGET_DB_URL=postgresql://... ./supabase/dr/replay.sh
#
# FROM_SEQ is `db.watermarks.audit_log` from the manifest of the dump you just
# restored. The work itself is in replay.sql next door; this only supplies the
# connection, the mount, and that one number.

set -euo pipefail

DR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${TAIL_DIR:?TAIL_DIR is required (a DECRYPTED tail directory)}"
: "${TARGET_DB_URL:?TARGET_DB_URL is required}"
: "${FROM_SEQ:?FROM_SEQ is required: db.watermarks.audit_log from the manifest of the restored dump}"
PG_IMAGE="${PG_IMAGE:-postgres:17}"
PGSSLMODE="${PGSSLMODE:-require}"

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
[ -f "$TAIL_DIR/audit_log.csv" ] || {
	echo "no audit_log.csv in $TAIL_DIR — is the tail still encrypted?" >&2; exit 1;
}

TAIL_ABS="$(cd "$TAIL_DIR" && pwd)"
CONTAINER_URL="$(printf '%s' "$TARGET_DB_URL" | sed -E 's#@(127\.0\.0\.1|localhost)([:/])#@host.docker.internal\2#')"

cp "$DR_DIR/replay.sql" "$TAIL_ABS/_replay.sql"
trap 'rm -f "$TAIL_ABS/_replay.sql"' EXIT

echo "==> Replaying $TAIL_ABS past seq $FROM_SEQ"
docker run --rm --user "$(id -u):$(id -g)" \
	--add-host=host.docker.internal:host-gateway \
	-v "$TAIL_ABS:/tail" \
	-e PGSSLMODE="$PGSSLMODE" \
	"$PG_IMAGE" \
	psql "$CONTAINER_URL" -q -v from_seq="$FROM_SEQ" -f /tail/_replay.sql
