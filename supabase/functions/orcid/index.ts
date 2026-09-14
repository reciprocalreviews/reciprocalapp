import 'edge-runtime';
import { createClient, SupabaseClient } from 'supabase';
import type { Database } from '../../../src/data/database.ts';
import { requireSecretKey } from '../_shared/auth.ts';
import {
	buildProfile,
	emptyProfile,
	orcidAPIURL,
	type ORCIDSection
} from '../_shared/orcidProfile.ts';

/**
 * Fetch the public ORCID record for a batch of scholars and write it to the mirror.
 *
 * Invoked only by the database, from private.claim_orcid_refresh, which has already
 * claimed every scholar in the batch by stamping fetch_attempted_at. That claim is what
 * bounds this: however many readers asked, the rows arrive here once per cooldown.
 *
 * This function is deliberately a thin shell. Everything worth testing -- reading ORCID's
 * deeply nested JSON, and above all counting works by GROUP rather than by summary -- is
 * in _shared/orcidProfile.ts, which vitest can reach. There is no test harness for edge
 * functions in this repo, so logic that lives here is logic nothing checks.
 */

/** ORCID's anonymous public API allows 12 requests a second. Four at a time leaves
 * headroom for whatever else shares this egress IP, and a batch of twenty scholars still
 * finishes inside a few seconds. */
const CONCURRENCY = 4;

/** Per request. ORCID is usually well under 500ms; anything near this is a stall, and the
 * batch matters more than the one scholar holding it up. */
const REQUEST_TIMEOUT_MS = 5000;

/** A ceiling on any single response. /works for a prolific record is 787KB uncompressed,
 * and gzip brings that to 37KB -- but the API is not bounded, and one pathological
 * consortium record should degrade rather than exhaust the function's memory. */
const MAX_BYTES = 8 * 1024 * 1024;

type Requested = { scholar: string; orcid: string; works: boolean };

type SectionResult =
	| { status: 'ok'; payload: unknown }
	| { status: 'not_found' }
	| { status: 'error'; detail: string };

async function fetchSection(orcid: string, section: ORCIDSection): Promise<SectionResult> {
	try {
		const response = await fetch(orcidAPIURL(orcid, section), {
			headers: {
				Accept: 'application/json',
				// Measured at 13-21x on real records, and the only bandwidth lever there is:
				// ORCID sends no ETag and ignores If-Modified-Since, so a conditional fetch
				// is not available. Deno's fetch decompresses transparently.
				'Accept-Encoding': 'gzip',
				// So ORCID can get in touch rather than block us.
				'User-Agent': 'ReciprocalReviews (+https://reciprocal.reviews)'
			},
			signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS)
		});

		// A record that does not exist, or was deactivated. Terminal, and cached as such:
		// retrying it every six hours forever would spend the daily budget on a certainty.
		if (response.status === 404 || response.status === 409) return { status: 'not_found' };
		if (!response.ok)
			return {
				status: 'error',
				detail: `${section}: HTTP ${response.status}${
					response.headers.get('Retry-After')
						? ` retry-after ${response.headers.get('Retry-After')}`
						: ''
				}`
			};

		const body = await response.text();
		if (body.length > MAX_BYTES)
			return { status: 'error', detail: `${section}: over ${MAX_BYTES} bytes` };
		return { status: 'ok', payload: JSON.parse(body) };
	} catch (error) {
		return {
			status: 'error',
			detail: `${section}: ${error instanceof Error ? error.message : error}`
		};
	}
}

/** Fetch one scholar's sections and reduce them to a row update.
 *
 * Partial success is per-section and deliberate: if /person answers and /employments
 * fails, the keywords are written and the employment columns are left as they were. A
 * partially refreshed row is strictly better than one emptied because a later request in
 * the same batch fell over. */
async function fetchScholar(requested: Requested) {
	const sections: ORCIDSection[] = ['person', 'employments', 'educations'];
	if (requested.works) sections.push('works');

	const results = new Map<ORCIDSection, SectionResult>();
	for (const section of sections)
		results.set(section, await fetchSection(requested.orcid, section));

	// Every section saying "no such record" is the record being gone. One section saying it
	// while others answer is not, so it is only terminal when they agree.
	if ([...results.values()].every((r) => r.status === 'not_found'))
		return { status: 'not_found' as const, update: {}, worksRead: false };

	const payloads: Record<string, unknown> = {};
	const failures: string[] = [];
	for (const [section, result] of results) {
		if (result.status === 'ok') payloads[section] = result.payload;
		else if (result.status === 'error') failures.push(result.detail);
		// A single not_found among answers is treated as "nothing there", which the
		// parser renders as absence anyway.
	}

	let parsed;
	try {
		parsed = buildProfile(payloads);
	} catch (error) {
		// buildProfile is total by construction, so this is defence rather than a path
		// anyone expects -- but a throw here would lose the rest of the batch.
		return {
			status: 'error' as const,
			update: {},
			worksRead: false,
			detail: `parse: ${error instanceof Error ? error.message : error}`
		};
	}

	const update: Record<string, unknown> = {};
	const column: Record<string, string> = {
		employmentRole: 'employment_role',
		employmentDepartment: 'employment_department',
		employmentOrganization: 'employment_organization',
		educationRole: 'education_role',
		educationOrganization: 'education_organization',
		educationYear: 'education_year',
		keywords: 'keywords',
		works: 'works',
		workCount: 'work_count',
		workFirstYear: 'work_first_year',
		workLastYear: 'work_last_year',
		links: 'links'
	};
	for (const [key, value] of Object.entries(parsed)) update[column[key]] = value;

	return {
		status: failures.length > 0 ? ('error' as const) : ('ok' as const),
		update,
		worksRead: 'works' in payloads,
		detail: failures.length > 0 ? failures.join('; ') : undefined
	};
}

async function writeScholar(
	supabase: SupabaseClient<Database>,
	requested: Requested,
	result: Awaited<ReturnType<typeof fetchScholar>>
) {
	// Re-read the iD before writing. The second of the two erasure guards: a batch claimed
	// just before an erasure would otherwise write the row back after forget_scholar
	// deleted it, restoring a name and an affiliation for somebody who asked to be
	// forgotten. The first guard is in claim_orcid_refresh, which skips a null iD.
	const { data: scholar } = await supabase
		.from('scholars')
		.select('orcid')
		.eq('id', requested.scholar)
		.maybeSingle();
	if (!scholar || scholar.orcid !== requested.orcid) return 'skipped';

	const now = new Date().toISOString();
	const base: Record<string, unknown> = {
		scholar: requested.scholar,
		orcid: requested.orcid,
		fetch_status: result.status,
		fetch_detail: result.detail ?? null,
		fetch_attempted_at: now
	};

	if (result.status === 'not_found') {
		// Cleared rather than left standing: the record is gone, and showing what it used
		// to say would be asserting something ORCID no longer does.
		const blank = emptyProfile();
		Object.assign(base, {
			employment_role: null,
			employment_department: null,
			employment_organization: null,
			education_role: null,
			education_organization: null,
			education_year: null,
			keywords: blank.keywords,
			works: blank.works,
			work_count: null,
			work_first_year: null,
			work_last_year: null,
			links: blank.links,
			fetched_at: now,
			fetch_failures: 0
		});
	} else {
		Object.assign(base, result.update);
		if (result.status === 'ok') {
			base.fetched_at = now;
			base.fetch_failures = 0;
			if (result.worksRead) base.works_fetched_at = now;
		} else {
			// Failed: keep whatever was already there and count the failure, so the
			// backoff in the next claim lengthens. fetched_at is deliberately untouched,
			// so the row still reports when it was last actually read.
			const { data: existing } = await supabase
				.from('orcid_profiles')
				.select('fetch_failures')
				.eq('scholar', requested.scholar)
				.maybeSingle();
			base.fetch_failures = Math.min((existing?.fetch_failures ?? 0) + 1, 32000);
			if (result.worksRead) base.works_fetched_at = now;
		}
	}

	const { error } = await supabase.from('orcid_profiles').upsert(base, { onConflict: 'scholar' });
	if (error) {
		console.error('orcid: could not write profile', requested.scholar, error);
		return 'failed';
	}
	return result.status;
}

/** Run tasks a few at a time. ORCID rate-limits per IP, and a batch of twenty fired at
 * once is a burst it would be right to reject. */
async function throttle<T>(items: T[], limit: number, run: (item: T) => Promise<unknown>) {
	let index = 0;
	const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
		while (index < items.length) {
			const item = items[index++];
			await run(item);
		}
	});
	await Promise.all(workers);
}

const handler = async (request: Request): Promise<Response> => {
	// The only gate: verify_jwt is off for this function, as it is for the others. Unlike
	// `resend` this is not an open relay even without it -- it takes only scholar ids and
	// iDs the database chose, and writes only to a derived cache -- but an open endpoint
	// that fans out to a third-party API on request is still somebody else's rate limit to
	// spend.
	const forbidden = await requireSecretKey(request);
	if (forbidden) return forbidden;

	try {
		const body = await request.json();
		const requested: Requested[] = Array.isArray(body?.scholars)
			? body.scholars.filter(
					(s: unknown): s is Requested =>
						typeof s === 'object' &&
						s !== null &&
						typeof (s as Requested).scholar === 'string' &&
						typeof (s as Requested).orcid === 'string'
				)
			: [];

		if (requested.length === 0)
			return new Response(JSON.stringify({ fetched: 0 }), {
				status: 200,
				headers: { 'Content-Type': 'application/json' }
			});

		const supabase = createClient<Database>(
			Deno.env.get('SUPABASE_URL') ?? '',
			Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
			{
				global: {
					headers: { Authorization: `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}` }
				}
			}
		);

		const counts: Record<string, number> = { ok: 0, not_found: 0, error: 0, skipped: 0, failed: 0 };
		await throttle(requested, CONCURRENCY, async (one) => {
			const result = await fetchScholar(one);
			const outcome = await writeScholar(supabase, one, result);
			counts[outcome] = (counts[outcome] ?? 0) + 1;
		});

		return new Response(JSON.stringify({ attempted: requested.length, ...counts }), {
			status: 200,
			headers: { 'Content-Type': 'application/json' }
		});
	} catch (error) {
		return new Response(
			JSON.stringify({ error: `Error refreshing ORCID profiles: ${JSON.stringify(error)}` }),
			{ status: 400, headers: { 'Content-Type': 'application/json' } }
		);
	}
};

Deno.serve(handler);
