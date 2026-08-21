import { error, type RequestHandler } from '@sveltejs/kit';

/**
 * Download everything the platform holds about one scholar, as JSON.
 *
 * The portability half of the promise on the terms page
 * (page.terms.paragraph.rights). Served as a download rather than rendered,
 * because the point is a file the scholar keeps, not a page they read.
 *
 * Authorization is the database's, not this route's: `export_scholar_data` is
 * SECURITY DEFINER and checks `auth.uid()` against the requested scholar, letting
 * a steward through for a request that arrives out of band. Doing it there rather
 * than here means a future caller — a CLI, a support script — cannot reach the
 * data by going around this endpoint.
 */
export const GET: RequestHandler = async ({ params, locals }) => {
	const scholarid = params.id;
	if (scholarid === undefined) error(400, 'No scholar specified');

	// The per-request, cookie-backed client from hooks.server.ts, so the RPC runs
	// as the signed-in scholar and auth.uid() is theirs.
	const { data, error: rpcError } = await locals.supabase.rpc('export_scholar_data', {
		_scholar: scholarid
	});

	// RR006 is the database saying this is not your account; anything else is a
	// fault rather than a refusal.
	if (rpcError) error(rpcError.code === 'RR006' ? 403 : 500, rpcError.message);

	const stamp = new Date().toISOString().slice(0, 10);
	return new Response(JSON.stringify(data, null, 2), {
		headers: {
			'Content-Type': 'application/json',
			// Named for the person's own filesystem, not ours.
			'Content-Disposition': `attachment; filename="reciprocal-reviews-${stamp}.json"`,
			// A copy of someone's personal data should never sit in a shared cache.
			'Cache-Control': 'no-store, private'
		}
	});
};
