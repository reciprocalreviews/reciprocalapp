import { expect, test } from '@playwright/test';
import { login, logout } from '../src/routes/login';
import { SEED, sql } from './test-utils';

/**
 * The mirrored slice of a scholar's public ORCID record.
 *
 * Entirely seed-driven. `npm run start:test` excludes the edge runtime, so the `orcid`
 * function cannot run and nothing here touches the network — which is the point: a suite
 * that asserted against live ORCID data would go red whenever ORCID had a bad afternoon,
 * and would be asserting somebody else's database anyway.
 *
 * Three of the five tests below are about ABSENCE, which is where the design decisions
 * are. A cold cache and a record with nothing public are the common cases, and both must
 * render as nothing at all rather than as a heading with blanks beneath it — a visitor
 * reading "Affiliation: —" is being told something false about a person.
 */

// Seeded with a full mirrored record.
const FULL = SEED.scholars.r1;
// Seeded with a row that was read and found to hold nothing public.
const EMPTY = SEED.scholars.r2;
// Seeded with no mirror row at all: the cold-cache case.
const COLD = SEED.scholars.editor;

test('a mirrored record shows who a scholar is, without leaving the page', async ({ page }) => {
	await page.goto(`/scholar/${FULL.id}`);

	const mirror = FULL.orcidProfile;
	await expect(page.getByTestId('orcid-affiliation')).toHaveText(mirror.affiliation);
	await expect(page.getByTestId('orcid-education')).toContainText(mirror.education);
	await expect(page.getByTestId('orcid-keywords')).toContainText(mirror.keyword);

	// The count spans the whole record, not just the few works kept, of which three
	// are listed.
	await expect(page.getByTestId('orcid-works')).toContainText(mirror.works);
	await expect(page.getByTestId('orcid-works')).toContainText(mirror.work);

	await expect(page.getByTestId('orcid-links')).toContainText(mirror.link);
});

test('the section says where it came from', async ({ page }) => {
	// Load-bearing rather than decorative: this line is what keeps the section from
	// reading as Reciprocal Reviews' own claim about a person.
	await page.goto(`/scholar/${FULL.id}`);
	await expect(page.getByTestId('orcid-provenance')).toContainText('From their ORCID record');

	// And the way out to everything RR does not mirror is still there, as the full URI
	// ORCID's display guidelines ask for.
	await expect(page.getByTestId('scholar-orcid')).toHaveAttribute(
		'href',
		`https://orcid.org/${FULL.orcid}`
	);
});

test('a record with nothing public renders as nothing, not as blanks', async ({ page }) => {
	await page.goto(`/scholar/${EMPTY.id}`);

	// The scholar's own page still works; it simply has no ORCID section.
	await expect(page.getByTestId('scholar-orcid')).toBeVisible();
	await expect(page.getByTestId('orcid-affiliation')).toHaveCount(0);
	await expect(page.getByTestId('orcid-works')).toHaveCount(0);
	await expect(page.getByTestId('orcid-provenance')).toHaveCount(0);
});

test('a scholar RR has never read renders without a section and without an error', async ({
	page
}) => {
	// The cold-cache case, which is every scholar on the day this ships. The page must be
	// entirely normal — this is the regression test for "a list page never breaks".
	await page.goto(`/scholar/${COLD.id}`);

	await expect(page.getByTestId('orcid-affiliation')).toHaveCount(0);
	await expect(page.getByTestId('orcid-problem')).toHaveCount(0);
	// Everything else on the page is unaffected.
	await expect(page.getByTestId('commitment-0')).toBeVisible();
});

test('a visitor is never told that a record could not be read', async ({ page }) => {
	// Only the scholar themselves sees that, and only on their own profile: on a public
	// page it reads as an accusation, may only mean ORCID was down when we asked, and the
	// visitor can do nothing about it either way.
	await page.goto(`/scholar/${EMPTY.id}`);
	await expect(page.getByTestId('orcid-problem')).toHaveCount(0);
});

test('ORCID keywords are marked as ORCID\u2019s wherever they appear', async ({ page }) => {
	// The mark travels with the chips rather than sitting on a rule above them, which is
	// what makes it read the same whether or not venue expertise sits above \u2014 see
	// ORCIDKeywords.svelte. Asserting the mark is inside the group is asserting exactly that.
	await page.goto(`/scholar/${FULL.id}`);
	const keywords = page.getByTestId('orcid-keywords');
	await expect(keywords.locator('svg.mark')).toHaveCount(1);
	// Announced, not a title attribute: a `title` on a span is not reliably read out.
	await expect(keywords).toContainText('From ORCID');
});

test('a steward sees how the mirror is doing, and can refresh it', async ({ page, context }) => {
	// The only operational surface the mirror has. Without it there is no way to populate
	// the mirror at all — running the function in a SQL editor is refused for want of an
	// auth.uid() — and no way to tell whether ORCID is refusing reads.
	await login(SEED.scholars.editor.email, page, context);
	await page.goto('/about');

	const card = page.getByTestId('refresh-orcid-card');
	await expect(card).toBeVisible();
	// The control has to be reachable without opening anything: a Card hides its children
	// until expanded, and this one's only child is the button.
	await expect(page.getByTestId('refresh-orcid-button')).toBeVisible();
	// Counts, not just "done" — a steward who sees only "done" cannot tell a batch from the
	// end of the queue.
	await expect(card).toContainText('never read');

	await logout(page);
});

test('a scholar who is not a steward sees no ORCID controls', async ({ page, context }) => {
	await login(SEED.scholars.author1.email, page, context);
	await page.goto('/about');
	await expect(page.getByTestId('refresh-orcid-card')).toHaveCount(0);
	await expect(page.getByTestId('refresh-orcid-button')).toHaveCount(0);
	await logout(page);
});

test('the rate-limit warning appears only when ORCID has actually been limiting reads', async ({
	page,
	context
}) => {
	// A permanent "0 rate limited" line would be noise on every visit and would stop being
	// read long before the day it mattered.
	await login(SEED.scholars.editor.email, page, context);
	await page.goto('/about');
	await expect(page.getByTestId('orcid-rate-limited')).toHaveCount(0);

	// Captured so the row can be put back as it was. It used to be DELETED afterwards, which
	// is not the same thing: r1 is the one scholar the seed gives a full mirror, so deleting
	// it left every later test in this file looking at a scholar with no ORCID record at all.
	const before = sql(
		`select fetch_status::text || '|' || coalesce(fetch_rate_limited_at::text, '') from public.orcid_profiles where scholar = '${SEED.scholars.r1.id}'`
	);

	try {
		// One statement on one line: sql() hands it straight to `docker exec`, where
		// embedded newlines and tabs break the shell quoting.
		const insert =
			`insert into public.orcid_profiles (scholar, orcid, fetch_status, fetch_rate_limited_at) ` +
			`values ('${SEED.scholars.r1.id}', '${SEED.scholars.r1.orcid}', 'error', now()) ` +
			`on conflict (scholar) do update set fetch_status = 'error', fetch_rate_limited_at = now()`;
		sql(insert);
		await page.reload();
		await expect(page.getByTestId('orcid-rate-limited')).toBeVisible();
	} finally {
		// Restored: the suite shares one seeded database.
		if (before.length === 0) {
			sql(`delete from public.orcid_profiles where scholar = '${SEED.scholars.r1.id}'`);
		} else {
			const [status, limited] = before.split('|');
			sql(
				`update public.orcid_profiles set fetch_status = '${status}', fetch_rate_limited_at = ${limited.length > 0 ? `'${limited}'` : 'null'} where scholar = '${SEED.scholars.r1.id}'`
			);
		}
	}
	await logout(page);
});

test('a record that lists something twice still leaves the page working', async ({
	page,
	context
}) => {
	/**
	 * The regression this suite exists to prevent from recurring, and it is worth stating
	 * plainly because the symptom was so quiet.
	 *
	 * The works and links lists used to be keyed `{#each}` blocks, keyed on their own
	 * content because neither a work nor a link has an id. An ORCID record may legally list
	 * the same identifier or the same paper twice — one real record carried its ResearcherID
	 * twice over — and a duplicate key THROWS in Svelte, in production as well as in
	 * development. The throw escaped hydration, so the server-rendered page stayed on screen:
	 * complete, styled, and wired to nothing. A scholar clicked Accept on an invitation for
	 * weeks and watched it depress and do nothing, because `:active` is CSS and needs no
	 * JavaScript at all.
	 *
	 * So this asserts the page is ALIVE, not that it looks right.
	 */
	const linksBefore = sql(
		`select links::text from public.orcid_profiles where scholar = '${FULL.id}'`
	);
	const worksBefore = sql(
		`select works::text from public.orcid_profiles where scholar = '${FULL.id}'`
	);
	const quote = (value: string) => value.replaceAll("'", "''");

	try {
		// Transcribed from the record that broke: the same identifier either side of another.
		// One statement on one line; sql() hands it to `docker exec`, where newlines break
		// the shell quoting.
		const links =
			`[{"kind":"identifier","label":"ResearcherID","value":"D-1001-2018","url":null},` +
			`{"kind":"identifier","label":"Scopus Author ID","value":"56732624800","url":null},` +
			`{"kind":"identifier","label":"ResearcherID","value":"D-1001-2018","url":null}]`;
		// And the same trap in the other list: one paper the record holds twice.
		const works =
			`[{"title":"On the Reproducibility of Reviewing","year":2025,"journal":"Journal of Rigor","doi":"10.1234/rigor.2025","url":null},` +
			`{"title":"Measuring Reviewer Load","year":2023,"journal":"Journal of Rigor","doi":"10.1234/load.2023","url":null},` +
			`{"title":"Measuring Reviewer Load","year":2023,"journal":"Journal of Rigor","doi":"10.1234/load.2023","url":null}]`;
		sql(
			`update public.orcid_profiles set links = '${links}'::jsonb, works = '${works}'::jsonb where scholar = '${FULL.id}'`
		);

		await login(FULL.email, page, context);
		await page.goto(`/scholar/${FULL.id}`);
		await page.waitForLoadState('networkidle');

		// 1. The app mounted at all. The root layout removes this class in onMount, so it
		//    outlives a hydration throw — and it is message-independent, which matters
		//    because Svelte's production error text is a bare URL.
		await expect(page.locator('body')).not.toHaveClass(/hydrating/);

		// 2. The reported symptom, exactly. Accept is a confirm button, so a first click has
		//    only to reach the confirm step: no network, no state, purely proof that the
		//    handler is attached. Asserted on the ellipsis Button appends to any warning
		//    button rather than on a locale string.
		const accept = page.getByTestId('invitation-accept-0');
		await expect(accept).toHaveText(/…$/);
		await accept.click();
		await expect(accept).not.toHaveText(/…$/);

		// 3. And each entry shown ONCE. Survival and correctness are different claims, and
		//    only this one fails if the lists are unkeyed but nothing deduplicates them.
		const shown = await page.getByTestId('orcid-links').innerText();
		expect(shown.match(/ResearcherID/g)).toHaveLength(1);
		await expect(page.getByTestId('orcid-works').locator('li')).toHaveCount(2);
	} finally {
		// Restored: the suite shares one seeded database, and this row is read by the
		// volunteers roster and the assignment table too. Guarded, because a jsonb literal
		// is parsed whether or not any row matches — an empty capture would fail here and
		// bury whatever the test was actually reporting.
		if (linksBefore.length > 0 && worksBefore.length > 0)
			sql(
				`update public.orcid_profiles set links = '${quote(linksBefore)}'::jsonb, works = '${quote(worksBefore)}'::jsonb where scholar = '${FULL.id}'`
			);
		await logout(page);
	}
});
