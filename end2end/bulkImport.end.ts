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

// The person column decides who holds a submission and who is paid for it, so the
// behaviour worth pinning in the browser is that an unmatched name stops the import
// rather than being guessed at. The discrimination between seated roles is left to
// the pgTAP tests, which can build a venue with several editors; the seed has one.
test('an editor named in the import must be one the venue knows', async ({ page, context }) => {
	await login('editor@uni.edu', page, context);

	await page.goto(`/venue/${VENUE_PATH}/submissions/import`);
	await page.waitForLoadState('networkidle');

	const external = `import-person-${Date.now()}`;
	await page.getByTestId('import-row-0-title').fill('Pre-launch paper with an editor');
	await page.getByTestId('import-row-0-externalid').fill(external);

	// Choose the role to seat into, which is what turns the person column on.
	await page.getByLabel('seat the named editor as').selectOption({ label: 'Editor' });

	// A name nobody at this venue holds blocks the import.
	await page.getByTestId('import-row-0-person').fill('Nobody Here');
	await expect(page.getByTestId('bulk-import-submit')).toBeDisabled();

	// The venue's own editor resolves, and the import goes through.
	await page.getByTestId('import-row-0-person').fill('Scholar Lee');
	await expect(page.getByTestId('bulk-import-submit')).toBeEnabled();
	await page.getByTestId('bulk-import-submit').click();

	await page.waitForURL(`**/venue/${VENUE_PATH}/submissions`);
	await expect(page.getByText(external)).toBeVisible();

	await logout(page);
});
