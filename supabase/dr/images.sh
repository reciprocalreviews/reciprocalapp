# Sourced by the DR scripts, not executed.
#
# Pull a container image before the first `docker run` that needs it, retrying
# with backoff. ECR Public throttles anonymous pulls per source IP, and
# GitHub-hosted runners share IPs, so a single `toomanyrequests: Rate exceeded`
# can arrive on a run that did nothing wrong. Moving off Docker Hub (95a18c4)
# made that rarer, not impossible: the nightly backup failed on exactly this on
# 2026-10-12, before touching the database. An implicit pull inside `docker run`
# gets one attempt; this gets five, over about two and a half minutes.
#
# An image already present locally is used as-is, so a run during an incident
# does not need the registry to be reachable at all.

pull_image() {
	local image="$1"
	local backoff="${PULL_BACKOFF:-10}"
	local attempt
	docker image inspect "$image" >/dev/null 2>&1 && return 0
	for attempt in 1 2 3 4 5; do
		docker pull -q "$image" >/dev/null && return 0
		[ "$attempt" -eq 5 ] && break
		echo "  pull of $image failed (attempt $attempt/5); retrying in ${backoff}s" >&2
		sleep "$backoff"
		backoff=$((backoff * 2))
	done
	echo "could not pull $image after 5 attempts; set PG_IMAGE / ALPINE_IMAGE to a reachable mirror" >&2
	return 1
}
