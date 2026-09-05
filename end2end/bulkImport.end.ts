import { test, expect } from '@playwright/test';
import { login, logout } from '../src/routes/login';
import { SEED } from './test-utils';

const VENUE_PATH = SEED.venuePath;

test('admin can bulk import free submissions and a proposed mint transaction', async ({
	page,
	context
}) => {
	await login('editor@uni.edu', page, context);

	await page.goto(`/venue/${VENUE_PATH}/submissions/import`);
	await page.waitForLoadState('networkidle');

	const externalA = `import-a-${Date.now()}`;
	const externalB = `import-b-${Date.now()}`;

	// Fill the first row.
	await page.getByTestId('import-row-0-title').fill('Pre-launch paper A');
	await page.getByTestId('import-row-0-externalid').fill(externalA);

	// Add a second row and fill it.
	await page.getByTestId('bulk-import-add-row').click();
	await page.getByTestId('import-row-1-title').fill('Pre-launch paper B');
	await page.getByTestId('import-row-1-externalid').fill(externalB);

	// Submit the import.
	await page.getByTestId('bulk-import-submit').click();

	// Should redirect back to the submissions index.
	await page.waitForURL(`**/venue/${VENUE_PATH}/submissions`);

	// Verify both imported submissions show up.
	await expect(page.getByText(externalA)).toBeVisible();
	await expect(page.getByText(externalB)).toBeVisible();

	// And that the list does not claim anybody paid for them. Nobody did: an
	// imported submission is free by construction, and the tokens meant to fund
	// its reviewing are still an unapproved mint. Anchored to the row for this
	// import rather than to a row index, since the venue already holds others.
	const row = page.locator('tr', { hasText: externalA });
	await expect(row.locator('[data-testid$="-payment"]')).toHaveText('free');

	await logout(page);
});

// An unmatched editor name must NOT stop the import. A backlog is exactly the case
// where the people named in the file have not signed up yet, and refusing it there
// made the feature useless where it mattered most — an unmatched name seats nobody,
// so there is no wrong person to seat. Ambiguity is the case that still blocks, and
// matchPersonName.unit.ts covers that; the seed has no two volunteers sharing a name.
test('a name the venue does not know imports with nobody in that role', async ({
	page,
	context
}) => {
	await login('editor@uni.edu', page, context);

	await page.goto(`/venue/${VENUE_PATH}/submissions/import`);
	await page.waitForLoadState('networkidle');

	const external = `import-unmatched-${Date.now()}`;

	// A CSV is what reveals the matching panel, so drive the paste path rather than
	// the file picker, which Playwright cannot open.
	await page
		.getByTestId('bulk-import-paste')
		.fill(`title,externalid,handling editor\nPre-launch paper,${external},Nobody Here`);
	await page.getByTestId('bulk-import-parse').click();

	// The importer never guesses which column names which role — that is venue
	// semantics — so match it by hand. The seed venue's top role is "Editor".
	await page
		.locator('[data-testid^="role-column-"]')
		.first()
		.selectOption({ label: 'handling editor' });

	// Reported in the cell, and counted before submitting, but not blocking.
	await expect(page.getByTestId('import-row-0-unmatched')).toBeVisible();
	await expect(page.getByTestId('bulk-import-submit')).toBeEnabled();

	await page.getByTestId('bulk-import-submit').click();
	await page.waitForURL(`**/venue/${VENUE_PATH}/submissions`);
	await expect(page.getByText(external)).toBeVisible();

	await logout(page);
});

// The other half: a name the venue does know is seated.
test('an editor the venue knows is matched and seated', async ({ page, context }) => {
	await login('editor@uni.edu', page, context);

	await page.goto(`/venue/${VENUE_PATH}/submissions/import`);
	await page.waitForLoadState('networkidle');

	const external = `import-person-${Date.now()}`;

	await page
		.getByTestId('bulk-import-paste')
		.fill(`title,externalid,handling editor\nPre-launch paper,${external},Scholar Lee`);
	await page.getByTestId('bulk-import-parse').click();

	await page
		.locator('[data-testid^="role-column-"]')
		.first()
		.selectOption({ label: 'handling editor' });

	await expect(page.getByTestId('import-row-0-unmatched')).toHaveCount(0);
	await page.getByTestId('bulk-import-submit').click();

	await page.waitForURL(`**/venue/${VENUE_PATH}/submissions`);
	await expect(page.getByText(external)).toBeVisible();

	await logout(page);
});

// Reading a file used to produce no output at all unless it failed, and the rows
// arrived below the fold.
test('parsing a CSV says what it read', async ({ page, context }) => {
	await login('editor@uni.edu', page, context);

	await page.goto(`/venue/${VENUE_PATH}/submissions/import`);
	await page.waitForLoadState('networkidle');

	await page
		.getByTestId('bulk-import-paste')
		.fill('title,externalid\nA paper,csv-loaded-1\nAnother,csv-loaded-2');
	await page.getByTestId('bulk-import-parse').click();

	await expect(page.getByTestId('csv-loaded')).toContainText('2 submissions');

	await logout(page);
});
