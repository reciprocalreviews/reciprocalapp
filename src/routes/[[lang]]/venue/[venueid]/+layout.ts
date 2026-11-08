import { redirect } from '@sveltejs/kit';
import { venuePath } from '#lib/data/venuePath.js';
import type { LayoutLoad } from './$types.js';

export const load: LayoutLoad = async ({ parent, params, url }) => {
	const { db, scholar } = await parent();

	// The segment is the venue's web address once it has one, and its id until then; both
	// resolve, so mail already sent and bookmarks already saved still land.
	const { data: venue } = await db.getVenueByPath(params.venueid);

	// Having landed, move to the canonical address. A temporary redirect, not a permanent
	// one: browsers cache a 308 indefinitely, and this target stops existing the moment
	// somebody renames the venue — which they are allowed to do, and warned about when
	// they do.
	if (venue !== null && venue.slug !== null && params.venueid !== venue.slug)
		redirect(
			307,
			url.pathname.replace(`/venue/${params.venueid}`, `/venue/${venuePath(venue)}`) + url.search
		);

	// An inactive venue admits its admins, and anyone with work still under way there, so a
	// closed venue's work can finish (#42). Asked only when it decides something.
	const participant =
		venue !== null &&
		venue.inactive !== null &&
		scholar !== null &&
		!venue.admins.includes(scholar.id)
			? ((await db.isVenueParticipant(venue.id, scholar.id)).data ?? false)
			: false;

	return {
		venue,
		participant
	};
};
