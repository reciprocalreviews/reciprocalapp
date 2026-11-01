import { expect, test } from '@playwright/test';
import { login } from '../src/routes/login';
import { SEED, sql } from './test-utils';

// The volunteers roster ranks volunteers by evidence of fit, for those who assign: reviews
// finished at the venue, and works in venues the venue lists as relevant. The Suggested
// view lists only those with a track record; Everyone lists the rest after them.

const VENUE_ID = SEED.venue;
const VENUE_PATH = SEED.venuePath;
const EDITOR_EMAIL = SEED.scholars.editor.email;
// Reviewer with finished reviews at the seed venue.
const REVIEWED = SEED.scholars.r2;
// Reviewer with no finished work and, until a spec gives them one, no ORCID mirror.
const UNPROVEN = SEED.scholars.r4;
// A venue name no seeded record mentions, so the only match is the one a spec plants.
const RELEVANT_TITLE = 'Proceedings of the 3rd Symposium on Imaginary Results 2024';

function reviewerRow(page: import('@playwright/test').Page, name: string) {
	return page.locator('tr[data-testid^="volunteer-row-"]', { hasText: name });
}

test.afterEach(() => {
	sql(`update public.venues set relevant_venues = '{}' where id = '${VENUE_ID}';`);
	sql(`delete from public.orcid_profiles where scholar = '${UNPROVEN.id}';`);
	sql(
		`delete from public.volunteers v using public.roles r where r.id = v.roleid and r.venueid = '${VENUE_ID}' and r.name = 'Associate Editor' and v.scholarid = '${UNPROVEN.id}';`
	);
});

test('a reviewer who has held an invite-only role here is suggested, and says which', async ({
	page,
	context
}) => {
	// A former associate editor, with no finished reviews and no ORCID mirror: the role
	// alone is the track record. Invite-only, so nobody could have given it to themselves.
	sql(
		`insert into public.volunteers (scholarid, roleid, expertise, accepted, active) select '${UNPROVEN.id}', id, '', 'accepted', false from public.roles where venueid = '${VENUE_ID}' and name = 'Associate Editor' and invited;`
	);

	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_PATH}/volunteers`);
	await expect(page.getByTestId('volunteer-view-suggested')).toHaveAttribute(
		'aria-pressed',
		'true'
	);

	// Their Reviewer row is suggested and badged with the role they held.
	const reviewerRow = page.locator('tr[data-testid^="volunteer-row-2-"]', {
		hasText: UNPROVEN.name
	});
	await expect(reviewerRow.getByTestId('volunteer-role-held')).toHaveText(
		'Former Associate Editor'
	);
});

test('an editor sees reviewers with a track record first, and the rest on request', async ({
	page,
	context
}) => {
	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_PATH}/volunteers`);
	await expect(page.getByTestId('volunteer-view-suggested')).toHaveAttribute(
		'aria-pressed',
		'true'
	);

	// Suggested: the reviewer who has finished work here, badged; not the one who has not.
	await expect(
		reviewerRow(page, REVIEWED.name).getByTestId('volunteer-reviewed-here')
	).toBeVisible();
	await expect(reviewerRow(page, UNPROVEN.name)).toHaveCount(0);

	// The hidden volunteers are counted, and one click away.
	await page.getByTestId('volunteer-show-everyone').first().click();
	await expect(page.getByTestId('volunteer-view-everyone')).toHaveAttribute('aria-pressed', 'true');
	await expect(reviewerRow(page, UNPROVEN.name)).toHaveCount(1);
	await expect(reviewerRow(page, UNPROVEN.name).getByTestId('volunteer-track')).toHaveCount(0);

	// In Everyone, those with a track record come before those without.
	const names = await page.locator('tr[data-testid^="volunteer-row-2-"]').allTextContents();
	const reviewedAt = names.findIndex((n) => n.includes(REVIEWED.name));
	const unprovenAt = names.findIndex((n) => n.includes(UNPROVEN.name));
	expect(reviewedAt).toBeGreaterThanOrEqual(0);
	expect(reviewedAt).toBeLessThan(unprovenAt);
	await expect(page.getByTestId('volunteer-no-record-2')).toBeVisible();
});

test('a relevant venue set in settings previews its matches and suggests who published there', async ({
	page,
	context
}) => {
	sql(
		`insert into public.orcid_profiles (scholar, orcid, work_journals, fetch_status, fetched_at, works_fetched_at, fetch_attempted_at) ` +
			`values ('${UNPROVEN.id}', '${UNPROVEN.orcid}', '[{"journal": "${RELEVANT_TITLE}", "count": 2}]', 'ok', now(), now(), now()) ` +
			`on conflict (scholar) do update set work_journals = excluded.work_journals;`
	);

	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_PATH}/settings`);

	// The ordinal, the year and "Proceedings of the" in the title do not stop a match.
	await page.getByTestId('venue-relevant-venues-toggle').click();
	await page
		.getByTestId('venue-relevant-venues')
		.fill('Symposium on Imaginary Results, SIR\nJournal Nobody Publishes In');
	await page.getByTestId('venue-relevant-venues-toggle').click();

	await expect
		.poll(() =>
			sql(
				`select array_to_string(relevant_venues, '|') from public.venues where id = '${VENUE_ID}';`
			)
		)
		.toBe('Symposium on Imaginary Results, SIR|Journal Nobody Publishes In');
	const preview = page.getByTestId('venue-relevant-preview');
	await expect(preview).toContainText('1 volunteer(s) have published here');
	await expect(preview).toContainText(RELEVANT_TITLE);
	await expect(preview).toContainText('no volunteers match yet');

	// The roster now suggests them, and says where.
	await page.goto(`/venue/${VENUE_PATH}/volunteers`);
	const row = reviewerRow(page, UNPROVEN.name);
	await row.getByTestId('volunteer-published').click();
	await expect(row).toContainText(RELEVANT_TITLE);
});

test('a volunteer who assigns nobody sees the plain roster, without the ranking', async ({
	page,
	context
}) => {
	await login(UNPROVEN.email, page, context);
	await page.goto(`/venue/${VENUE_PATH}/volunteers`);
	await expect(page.getByTestId('volunteer-filter')).toBeVisible();
	await expect(page.getByTestId('volunteer-view-suggested')).toHaveCount(0);
	await expect(page.getByTestId('volunteer-track')).toHaveCount(0);
});
