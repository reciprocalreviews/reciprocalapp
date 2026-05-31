import { execSync } from 'child_process';
import { expect, test } from '@playwright/test';
import { login } from '../src/routes/login';

const VENUE_ID = 'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6';
const CURRENCY_ID = 'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac';
const EDITOR_EMAIL = 'editor@uni.edu';
const MINTER_EMAIL = 'r1@uni.edu';
const RECIPIENT_EMAIL_FOR_GIFT = 'author2@uni.edu';
const SECOND_EDITOR_EMAIL = 'author2@uni.edu';
const SECOND_MINTER_EMAIL = 'r2@uni.edu';
const NON_EDITOR_EMAIL = 'r3@uni.edu';

function sql(statement: string): string {
	return execSync(
		`docker exec supabase_db_reciprocalapp psql -U postgres -d postgres -t -A -c ${JSON.stringify(statement)}`,
		{ encoding: 'utf-8' }
	).trim();
}

test('editor edits venue title, description, and URL', async ({ page, context }) => {
	// Snapshot the original values so we can restore them at the end — keeps
	// manual exploration after an e2e run from finding a venue with the
	// rename/description gibberish still applied.
	const originalTitle = sql(`select title from public.venues where id = '${VENUE_ID}';`);
	const originalDescription = sql(
		`select description from public.venues where id = '${VENUE_ID}';`
	);
	const originalUrl = sql(`select url from public.venues where id = '${VENUE_ID}';`);

	try {
		await login(EDITOR_EMAIL, page, context);

		// Description and URL live on /venue/[id].
		await page.goto(`/venue/${VENUE_ID}`);
		await page.waitForLoadState('networkidle');

		const newDescription = `Description updated by e2e at ${Date.now()}`;
		const newUrl = `https://example.com/e2e-${Date.now()}`;

		await page.getByTestId('venue-description-toggle').click();
		await page.getByTestId('venue-description').fill(newDescription);
		await page.getByTestId('venue-description-toggle').click();
		await expect(page.getByText(newDescription)).toBeVisible();

		await page.getByTestId('venue-url-toggle').click();
		await page.getByTestId('venue-url').fill(newUrl);
		await page.getByTestId('venue-url-toggle').click();
		// Poll the DB so we don't race the in-flight save when reloading.
		await expect
			.poll(() => sql(`select url from public.venues where id = '${VENUE_ID}';`))
			.toBe(newUrl);

		// Title lives in the page header (Nav.svelte) on any venue route. Edit it
		// from /venue/[id]/settings.
		await page.goto(`/venue/${VENUE_ID}/settings`);
		await page.waitForLoadState('networkidle');

		const newTitle = `Renamed by e2e ${Date.now()}`;
		await page.getByTestId('page-title-edit-toggle').click();
		await page.getByTestId('page-title-edit').fill(newTitle);
		await page.getByTestId('page-title-edit-toggle').click();
		await page.waitForTimeout(500);
		expect(sql(`select title from public.venues where id = '${VENUE_ID}';`)).toBe(newTitle);
	} finally {
		// Restore the originals so subsequent manual testing finds the seeded
		// venue intact. Pg-escape single quotes by doubling them.
		const esc = (s: string) => s.replaceAll("'", "''");
		sql(
			`update public.venues set title = '${esc(originalTitle)}', description = '${esc(originalDescription)}', url = '${esc(originalUrl)}' where id = '${VENUE_ID}';`
		);
	}
});

test('editor adds and removes another editor; last-editor constraint blocks removing the only one', async ({
	page,
	context
}) => {
	await login(EDITOR_EMAIL, page, context);

	await page.goto(`/venue/${VENUE_ID}/settings`);
	await page.waitForLoadState('networkidle');

	// At seed, the venue has one admin and the "remove admin" button isn't
	// rendered at all (the markup only renders it when admins.length > 1).
	// That's the last-editor invariant surfaced in the UI.
	await expect(page.getByTestId('remove-admin-0')).toHaveCount(0);

	// Add a second admin.
	await page.getByTestId('add-admin-field').fill(SECOND_EDITOR_EMAIL);
	await page.getByTestId('add-admin-button').click();

	// The second admin is now present in the venue's admins list (verify via
	// DB rather than UI text, which can vary).
	await expect
		.poll(() => Number(sql(`select cardinality(admins) from public.venues where id = '${VENUE_ID}';`)))
		.toBe(2);

	// Remove buttons should now be visible (one per admin).
	await expect(page.getByTestId('remove-admin-0')).toBeVisible();

	// Remove the newly-added admin. removeAdmin is a confirm button — click
	// once to enter confirm mode, then again to actually remove. Index
	// corresponds to admin position; the original editor is at 0.
	await page.getByTestId('remove-admin-1').click();
	await page.getByTestId('remove-admin-1').click();
	await expect
		.poll(() => Number(sql(`select cardinality(admins) from public.venues where id = '${VENUE_ID}';`)))
		.toBe(1);

	// Last-editor invariant: the remove button disappears once only one
	// admin remains.
	await expect(page.getByTestId('remove-admin-0')).toHaveCount(0);
});

test('minter adds and removes another minter; last-minter constraint blocks removing the only one', async ({
	page,
	context
}) => {
	await login(MINTER_EMAIL, page, context);

	await page.goto(`/currency/${CURRENCY_ID}`);
	await page.waitForLoadState('networkidle');

	// At seed, the currency has one minter; no remove button rendered.
	await expect(page.getByTestId('remove-minter-0')).toHaveCount(0);

	// Expand the add-minter card to reveal its form.
	await page.getByTestId('add-minter-card').click();
	await page.getByTestId('add-minter-field').fill(SECOND_MINTER_EMAIL);
	await page.getByTestId('add-minter-button').click();

	await expect
		.poll(() =>
			Number(sql(`select cardinality(minters) from public.currencies where id = '${CURRENCY_ID}';`))
		)
		.toBe(2);

	await expect(page.getByTestId('remove-minter-0')).toBeVisible();

	await page.getByTestId('remove-minter-1').click();
	await expect
		.poll(() =>
			Number(sql(`select cardinality(minters) from public.currencies where id = '${CURRENCY_ID}';`))
		)
		.toBe(1);

	await expect(page.getByTestId('remove-minter-0')).toHaveCount(0);
});

test('editor sets the venue inactive; non-editor sees the inactive notice on the venue page', async ({
	page,
	context
}) => {
	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/settings`);
	await page.waitForLoadState('networkidle');

	await page.getByTestId('inactive-checkbox').click();
	await expect
		.poll(() => sql(`select inactive is not null from public.venues where id = '${VENUE_ID}';`))
		.toBe('t');

	// Edit the inactive message to something distinctive so the test isn't
	// asserting on default seed text.
	const message = `Closed for e2e testing ${Date.now()}`;
	await page.getByTestId('venue-inactive-message-toggle').click();
	await page.getByTestId('venue-inactive-message').fill(message);
	await page.getByTestId('venue-inactive-message-toggle').click();
	await expect
		.poll(() => sql(`select inactive from public.venues where id = '${VENUE_ID}';`))
		.toBe(message);

	// Switch to a scholar with no admin role on this venue and verify the
	// inactive notice is what they see when visiting the venue page.
	await context.clearCookies();
	await login(NON_EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}`);
	await page.waitForLoadState('networkidle');
	await expect(page.getByTestId('venue-inactive-notice')).toBeVisible();
});

test('editor reactivates the venue; the inactive notice disappears for non-editors', async ({
	page,
	context
}) => {
	// Set inactive via SQL so this test doesn't depend on the previous one
	// having run, and so it cleans up after itself when reactivating below.
	sql(`update public.venues set inactive = 'temp' where id = '${VENUE_ID}';`);

	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/settings`);
	await page.waitForLoadState('networkidle');

	// Toggle the checkbox off to reactivate.
	await page.getByTestId('inactive-checkbox').click();
	await expect
		.poll(() => sql(`select inactive is null from public.venues where id = '${VENUE_ID}';`))
		.toBe('t');

	// A non-editor now sees the venue without the inactive notice.
	await context.clearCookies();
	await login(NON_EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}`);
	await page.waitForLoadState('networkidle');
	await expect(page.getByTestId('venue-inactive-notice')).toHaveCount(0);
});

test('editor edits welcome amount, submission cost, and per-role compensation', async ({
	page,
	context
}) => {
	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/settings`);
	await page.waitForLoadState('networkidle');

	// Change welcome amount.
	const originalWelcome = sql(
		`select welcome_amount from public.venues where id = '${VENUE_ID}';`
	);
	await page.getByTestId('venue-welcome-amount-toggle').click();
	await page.getByTestId('venue-welcome-amount').fill('25');
	await page.getByTestId('venue-welcome-amount-toggle').click();
	await expect
		.poll(() => sql(`select welcome_amount from public.venues where id = '${VENUE_ID}';`))
		.toBe('25');

	// Change a submission type's cost. Cost is now per submission type, edited in
	// the submission types table on the venue dashboard (not venue-wide settings).
	await page.goto(`/venue/${VENUE_ID}`);
	await page.waitForLoadState('networkidle');
	await page.getByTestId('submission-cost-0-toggle').click();
	await page.getByTestId('submission-cost-0').fill('12');
	await page.getByTestId('submission-cost-0-toggle').click();
	await expect
		.poll(() =>
			sql(
				`select count(*) from public.submission_types where venue = '${VENUE_ID}' and submission_cost = 12;`
			)
		)
		.toBe('1');

	// Return to the settings page for the remaining edits.
	await page.goto(`/venue/${VENUE_ID}/settings`);
	await page.waitForLoadState('networkidle');

	// Change Reviewer×Research Article compensation. The slider exposes a
	// stable testid `compensation-{role.name}-{type.name}`. Role cards on the
	// settings page now start collapsed, so expand the Reviewer card first.
	await page.getByTestId('role-Reviewer').click();
	const slider = page.getByTestId('compensation-Reviewer-Research Article');
	await expect(slider).toBeVisible();
	await slider.fill('7');
	// Slider commits on blur (immediately={false}).
	await slider.blur();
	await expect
		.poll(() =>
			sql(
				`select amount from public.compensation c join public.roles r on r.id = c.role join public.submission_types t on t.id = c.submission_type where r.name = 'Reviewer' and t.name = 'Research Article';`
			)
		)
		.toBe('7');

	// Restore the welcome amount so later tests (and usability scenarios) see
	// the seed value.
	await page.getByTestId('venue-welcome-amount-toggle').click();
	await page.getByTestId('venue-welcome-amount').fill(originalWelcome);
	await page.getByTestId('venue-welcome-amount-toggle').click();
});

test('editor toggles bidding off and back on for a role', async ({ page, context }) => {
	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/settings`);
	await page.waitForLoadState('networkidle');

	// Expand the Reviewer role card and its inner admin-settings card so
	// the biddable checkbox renders.
	await page.getByTestId('role-Reviewer').click();
	await page.getByTestId('role-settings-Reviewer').click();

	const reviewerRoleID = sql(
		`select id from public.roles where venueid = '${VENUE_ID}' and name = 'Reviewer';`
	);
	const biddable = page.getByTestId('role-biddable-Reviewer');
	await expect(biddable).toBeVisible();

	// Reviewer is biddable in the seed. Toggle off, verify, toggle back on.
	await biddable.click();
	await expect
		.poll(() => sql(`select biddable from public.roles where id = '${reviewerRoleID}';`))
		.toBe('f');

	await biddable.click();
	await expect
		.poll(() => sql(`select biddable from public.roles where id = '${reviewerRoleID}';`))
		.toBe('t');
});

test('editor gifts tokens from the venue reserve to a scholar', async ({ page, context }) => {
	await login(EDITOR_EMAIL, page, context);

	const recipientID = sql(
		`select id from public.scholars where email = '${RECIPIENT_EMAIL_FOR_GIFT}';`
	);
	const balanceBefore = Number(
		sql(
			`select count(*) from public.tokens where scholar = '${recipientID}' and currency = '${CURRENCY_ID}';`
		)
	);

	await page.goto(`/venue/${VENUE_ID}/transactions`);
	await page.waitForLoadState('networkidle');

	// Expand the gift card so its form is rendered.
	await page.getByTestId('venue-gift-card').click();
	await page.getByTestId('gift-recipient').fill(RECIPIENT_EMAIL_FOR_GIFT);
	await page.getByTestId('gift-amount').fill('3');
	await page.getByTestId('gift-purpose').fill('e2e gift test');
	await page.getByTestId('gift-consent').click();
	await page.getByTestId('gift-submit').click();

	// Recipient's balance should rise by exactly 3.
	await expect
		.poll(() =>
			Number(
				sql(
					`select count(*) from public.tokens where scholar = '${recipientID}' and currency = '${CURRENCY_ID}';`
				)
			)
		)
		.toBe(balanceBefore + 3);

	// A new approved transaction from the venue to the recipient was logged.
	const newTxnCount = Number(
		sql(
			`select count(*) from public.transactions where from_venue = '${VENUE_ID}' and to_scholar = '${recipientID}' and status = 'approved' and purpose = 'e2e gift test';`
		)
	);
	expect(newTxnCount).toBeGreaterThanOrEqual(1);
});

test('editor sees reviewing-platform email-template snippets and can copy them', async ({
	page,
	context
}) => {
	// Clipboard write needs an explicit grant on Chromium in CI environments;
	// granting both read and write so the assertion below can read it back.
	await context.grantPermissions(['clipboard-read', 'clipboard-write']);

	// Earlier tests in this file may have renamed the venue; query the live
	// title so assertions match what's actually rendered.
	const venueTitle = sql(`select title from public.venues where id = '${VENUE_ID}';`);

	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/settings`);
	await page.waitForLoadState('networkidle');

	// Default platform is HotCRP → its submission variable is {{PID}}.
	const paymentBody = page.getByTestId('template-payment');
	await expect(paymentBody).toContainText(venueTitle);
	await expect(paymentBody).toContainText('{{PID}}');
	await expect(paymentBody).toContainText(
		`https://reciprocal.reviews/venue/${VENUE_ID}/submissions/new?manuscript={{PID}}`
	);

	// Switch the platform selector to OJS; the snippet body should re-render
	// with OJS's {$submissionId} syntax.
	await page.locator('select').selectOption('ojs');
	await expect(paymentBody).toContainText('{$submissionId}');
	await expect(paymentBody).not.toContainText('{{PID}}');

	// Copy the snippet and verify the clipboard contains it.
	await page.getByTestId('template-payment-copy').click();
	const clipboard = await page.evaluate(() => navigator.clipboard.readText());
	expect(clipboard).toContain(venueTitle);
	expect(clipboard).toContain('{$submissionId}');

	// All three template cards render (acknowledgement + compensation also
	// present and update with the platform switch).
	await expect(page.getByTestId('template-acknowledgement')).toContainText('{$submissionId}');
	await expect(page.getByTestId('template-compensation')).toContainText('{$submissionId}');
});

test('deep-link pre-fill populates the new-submission form from a ?manuscript query', async ({
	page,
	context
}) => {
	// Editor visits the new-submission page with a manuscript ID query param,
	// as if they followed the link from a reviewing-platform-generated email.
	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/submissions/new?manuscript=TEST-001`);
	await page.waitForLoadState('networkidle');

	await expect(page.getByTestId('submission-manuscript-id')).toHaveValue('TEST-001');
});
