import { error } from '@sveltejs/kit';
import { isUUID } from '$lib/validation';
import type { LayoutLoad } from './$types';

export const load: LayoutLoad = async ({ parent, params }) => {
	const { db } = await parent();

	// A scholar id is a UUID. Rejecting a malformed one here rather than handing it to
	// PostgREST saves a round trip whose only outcome is a 22P02 the read layer logs
	// and discards — which the page then rendered as "unable to load your profile",
	// indistinguishable from a real outage.
	if (!isUUID(params.id)) error(404, 'No such scholar');

	// Get the scholar record
	const { data: scholar, error: failure } = await db.getScholarRow(params.id);

	// Absent is not the same as broken, and the page said the same thing for both. A
	// `.maybeSingle()` that finds nothing returns null with no failure, so that is a
	// 404 — the record does not exist, and saying so is the honest answer whether the
	// link is mistyped, stale, or points at an account whose scholar row never got
	// created. A failure falls through instead, and the page below keeps reporting
	// that it could not load — which is what that message was written for.
	if (scholar === null && failure === undefined) error(404, 'No such scholar');

	return {
		scholar
	};
};
