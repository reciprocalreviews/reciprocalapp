import { test, expect } from '@playwright/test';
import { login, logout } from '../src/routes/login';

const VENUE_ID = 'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6';

test('admin can bulk import free submissions and a proposed mint transaction', async ({
	page,
	context
}) => {
	await login('editor@uni.edu', page, context);

	await page.goto(`/venue/${VENUE_ID}/submissions/import`);
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
	await page.waitForURL(`**/venue/${VENUE_ID}/submissions`);
	await page.waitForLoadState('networkidle');

	// Verify both imported submissions show up.
	await expect(page.getByText(externalA)).toBeVisible();
	await expect(page.getByText(externalB)).toBeVisible();

	await logout(page);
});
