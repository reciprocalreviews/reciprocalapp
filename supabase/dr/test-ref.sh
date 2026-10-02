#!/usr/bin/env bash
#
# Print the commit whose tests belong with a backup.
#
# The drill restores the most recent backup and then runs the RLS suite against
# it. Run the suite from HEAD and any migration that landed after the backup was
# taken fails it: the tests expect a function the backed-up schema never had.
# That is version skew, not a broken backup, and a drill that goes red for it
# trains you to wave red drills through.
#
# The manifest's `git_sha` cannot answer this: it is whatever the BACKUP job
# checked out (dev, on a schedule), not what production was running. Its
# `db.migrations` list can, because it was read out of the database itself. So
# the answer is the newest commit on HEAD's first-parent line before the first
# one that adds a migration past the backup's newest — the latest tests written
# against exactly that schema.
#
#   ./supabase/dr/test-ref.sh manifest.json
#
# Prints a commit SHA on stdout. Falls back to HEAD (with a warning on stderr) if
# the history cannot place the backup, so the drill degrades to its old
# behaviour rather than failing on this script. Needs full history.

set -euo pipefail

MANIFEST="${1:?usage: test-ref.sh manifest.json}"
newest=$(jq -r '(.db.migrations // []) | max // empty' "$MANIFEST")
[ -n "$newest" ] || { echo "manifest has no migration list; using HEAD" >&2; git rev-parse HEAD; exit 0; }

# Highest migration version present in a commit's tree.
top() {
	git ls-tree --name-only "$1" supabase/migrations/ | sed -E 's#.*/([0-9]+)_.*#\1#' | sort | tail -1
}

ref=""
for c in $(git log --first-parent --reverse --format=%H HEAD -- supabase/migrations); do
	if [[ "$(top "$c")" > "$newest" ]]; then
		ref=$(git rev-parse "$c^")
		break
	fi
done
ref="${ref:-$(git rev-parse HEAD)}"

# Say so if the chosen tree still disagrees with the backup. Not fatal: a
# mismatch here is information for whoever reads the drill, and the suite is
# about to report anything it actually breaks.
want=$(jq -r '.db.migrations[]' "$MANIFEST" | sort)
have=$(git ls-tree --name-only "$ref" supabase/migrations/ | sed -E 's#.*/([0-9]+)_.*#\1#' | sort)
if [ "$want" != "$have" ]; then
	echo "warning: migrations at $(git rev-parse --short "$ref") do not exactly match the backup's:" >&2
	diff <(echo "$want") <(echo "$have") | grep '^[<>]' | sed 's/^</  only in backup:/; s/^>/  only in tree:  /' >&2 || true
fi

echo "$ref"
