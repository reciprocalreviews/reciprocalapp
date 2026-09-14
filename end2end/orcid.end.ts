import { expect, test } from '@playwright/test';
import { SEED } from './test-utils';

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

	await expect(page.getByTestId('orcid-affiliation')).toHaveText(
		'Professor, Department of Rigor, University of Test'
	);
	await expect(page.getByTestId('orcid-education')).toContainText('Ph.D. Reproducibility');
	await expect(page.getByTestId('orcid-keywords')).toContainText('peer review');

	// The count spans the whole record, not the few works kept: 37 works, of which three
	// are listed.
	await expect(page.getByTestId('orcid-works')).toContainText('37 works, 2009–2025');
	await expect(page.getByTestId('orcid-works')).toContainText(
		'On the Reproducibility of Reviewing'
	);

	await expect(page.getByTestId('orcid-links')).toContainText('Faculty website');
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
