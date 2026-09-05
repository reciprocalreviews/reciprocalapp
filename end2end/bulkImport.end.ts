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

	await logout(page);
});

// The editor columns decide who holds a submission and who is paid for it, so the
// behaviour worth pinning in the browser is that an unmatched name stops the import
// rather than being guessed at. Seating several roles at once, and the refusals
// around priority-0, are left to the pgTAP tests, which can build a venue with two
// editors and two top roles; the seed has one of each.
test('an editor named in the import must be one the venue knows', async ({ page, context }) => {
	await login('editor@uni.edu', page, context);

	await page.goto(`/venue/${VENUE_PATH}/submissions/import`);
	await page.waitForLoadState('networkidle');

	const external = `import-person-${Date.now()}`;

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

	// A name nobody at this venue holds blocks the import.
	await expect(page.getByTestId('bulk-import-submit')).toBeDisabled();

	// The venue's own editor resolves, and the import goes through.
	const cell = page.locator('[data-testid^="import-row-0-person-"]');
	await cell.fill('Scholar Lee');
	await expect(page.getByTestId('bulk-import-submit')).toBeEnabled();
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
