import { expect, test } from '@playwright/test';
import { login } from '../src/routes/login';
import { SEED } from './test-utils';

// The seed's closed venue, seen by its admin (the seeded editor). An inactive venue takes no
// new work (#42), so its admin is told it is inactive and is offered nothing that would start
// any: no new submission, no import, no volunteering. The database refuses all of it too
// (supabase/tests/rpc/inactive_venue.sql); this checks the interface does not offer it.
const VENUE_PATH = SEED.inactiveVenue.path;

test.beforeEach(async ({ page, context }) => {
	await login(SEED.scholars.editor.email, page, context);
});

test('an inactive venue offers its admin no new submission or volunteering', async ({ page }) => {
	await page.goto(`/venue/${VENUE_PATH}`);
	await page.waitForLoadState('networkidle');

	await expect(page.getByTestId('venue-inactive-prompt')).toBeVisible();
	await expect(page.getByTestId('venue-new-submission')).toHaveCount(0);
});

test('an inactive venue offers no new or imported submissions on its submissions page', async ({
	page
}) => {
	await page.goto(`/venue/${VENUE_PATH}/submissions`);
	await page.waitForLoadState('networkidle');

	await expect(page.getByTestId('submissions-new')).toHaveCount(0);
	await expect(page.getByTestId('submissions-import')).toHaveCount(0);
});

test('a saved link to the new-submission or import form says the venue is inactive', async ({
	page
}) => {
	for (const route of ['submissions/new', 'submissions/import']) {
		await page.goto(`/venue/${VENUE_PATH}/${route}`);
		await page.waitForLoadState('networkidle');
		await expect(page.getByTestId('venue-closed-to-submissions')).toBeVisible();
	}
});
