# Sourced by the DR scripts, not executed.
#
# Pull a container image before the first `docker run` that needs it, retrying
# with backoff and rotating across registries. Every anonymous registry throttles
# per source IP, and GitHub-hosted runners share IPs, so a run that did nothing
# wrong can be refused before it touches the database. That has happened three
# times: Docker Hub on 2026-10-09 (hence 95a18c4, moving to ECR Public), ECR
# Public's "Rate exceeded" on 2026-10-12 (hence the retries), and ECR Public's
# "Data limit exceeded" on 2026-10-13 — a monthly per-IP cap that no amount of
# retrying the same registry gets past. So each attempt walks every registry
# that mirrors the official image, and whichever answers is tagged with the
# requested name so the callers' `docker run` lines need not know which it was.
#
# An image already present locally is used as-is, so a run during an incident
# does not need any registry to be reachable at all. In CI the dr-images action
# loads both images from the Actions cache first, so this rarely pulls there.

# The same official Docker library image on each registry that serves it,
# requested reference first. A reference outside the library (a custom PG_IMAGE)
# has no known mirrors and is tried alone.
image_candidates() {
	local image="$1"
	local name mirror
	case "$image" in
	public.ecr.aws/docker/library/*) name="${image#public.ecr.aws/docker/library/}" ;;
	mirror.gcr.io/library/*) name="${image#mirror.gcr.io/library/}" ;;
	docker.io/library/*) name="${image#docker.io/library/}" ;;
	*/*) echo "$image"; return ;;
	*) name="$image" ;;
	esac
	echo "$image"
	for mirror in "public.ecr.aws/docker/library/$name" "mirror.gcr.io/library/$name" "docker.io/library/$name"; do
		[ "$mirror" = "$image" ] || echo "$mirror"
	done
}

pull_image() {
	local image="$1"
	local backoff="${PULL_BACKOFF:-10}"
	local attempt candidate
	docker image inspect "$image" >/dev/null 2>&1 && return 0
	for attempt in 1 2 3 4 5; do
		for candidate in $(image_candidates "$image"); do
			if docker pull -q "$candidate" >/dev/null; then
				[ "$candidate" = "$image" ] || docker tag "$candidate" "$image"
				[ "$candidate" = "$image" ] || echo "  pulled $image from $candidate" >&2
				return 0
			fi
		done
		[ "$attempt" -eq 5 ] && break
		echo "  pull of $image failed from every registry (attempt $attempt/5); retrying in ${backoff}s" >&2
		sleep "$backoff"
		backoff=$((backoff * 2))
	done
	echo "could not pull $image from any registry after 5 attempts; set PG_IMAGE / ALPINE_IMAGE to a reachable mirror" >&2
	return 1
}
