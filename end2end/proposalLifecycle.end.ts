import { expect, test } from '@playwright/test';
import { login } from '../src/routes/login';
import { SEED, sql } from './test-utils';

const STEWARD_EMAIL = SEED.scholars.editor.email; // editor@uni.edu has steward=true in seed
const PROPOSER_EMAIL = SEED.scholars.r2.email;
const SUPPORTER_EMAIL = SEED.scholars.r3.email;
const APPROVAL_MINTER_EMAIL = SEED.scholars.author2.email;

/** Insert a fresh pending proposal via SQL and return its ID. Used by
 * tests that operate on a proposal but don't need to test the propose-form
 * UI itself. */
function seedPendingProposal(title: string, editors: string[], minters: string[]): string {
	const editorsArray = `ARRAY[${editors.map((e) => `'${e}'`).join(',')}]::text[]`;
	const mintersArray = `ARRAY[${minters.map((m) => `'${m}'`).join(',')}]::text[]`;
	return sql(
		`insert into public.proposals (title, url, editors, minters, census, venue) values ('${title}', 'https://example.com', ${editorsArray}, ${mintersArray}, 100, null) returning id;`
	);
}

test('anonymous visitor sees proposed venues on /venues', async ({ page }) => {
	const title = `Anonymous-list-test ${Date.now()}`;
	seedPendingProposal(title, [STEWARD_EMAIL], [APPROVAL_MINTER_EMAIL]);

	await page.goto('/venues');

	// The proposal title appears in the proposals section.
	await expect(page.getByText(title).first()).toBeVisible();
});

test('authenticated scholar submits a new venue proposal', async ({ page, context }) => {
	const title = `Propose-form-test ${Date.now()}`;
	const url = 'https://example.com/test';
	const rationale = `e2e proposal ${Date.now()}`;

	await login(PROPOSER_EMAIL, page, context);
	await page.goto('/venues/proposal');
	await page.waitForLoadState('networkidle');

	// Click then pressSequentially each field. fill() alone occasionally fails
	// to trigger Svelte's bind:text propagation in this form (the submit
	// button is gated on the parent state values; if those don't update,
	// the button stays disabled).
	const fillField = async (testid: string, value: string) => {
		const field = page.getByTestId(testid);
		await field.click();
		await field.fill(value);
		await field.blur();
	};

	await fillField('propose-venue-name', title);
	await fillField('propose-venue-editors', STEWARD_EMAIL);
	// The currency Options defaults to "Create a new currency" (undefined),
	// which makes the minters field required.
	await fillField('propose-venue-minters', APPROVAL_MINTER_EMAIL);
	await fillField('propose-venue-url', url);
	await fillField('propose-venue-size', '250');
	await fillField('propose-venue-rationale', rationale);

	const submitButton = page.getByTestId('propose-venue-submit');
	await expect(submitButton).toBeEnabled({ timeout: 5_000 });
	await submitButton.click();

	// On success the page redirects to the new proposal's detail page.
	await page.waitForURL(/\/venues\/proposal\/[0-9a-f-]+$/);

	// The proposal exists in the DB with the values from the form.
	const row = sql(
		`select title, url, census, editors[1] from public.proposals where title = '${title}';`
	);
	expect(row).toBe(`${title}|${url}|250|${STEWARD_EMAIL}`);
});

test('authenticated scholar supports a proposal', async ({ page, context }) => {
	const title = `Support-test ${Date.now()}`;
	const proposalID = seedPendingProposal(title, [STEWARD_EMAIL], [APPROVAL_MINTER_EMAIL]);

	const supporterID = sql(`select id from public.scholars where email = '${SUPPORTER_EMAIL}';`);
	// Reset support state so the test is repeatable.
	sql(
		`delete from public.supporters where scholarid = '${supporterID}' and proposalid = '${proposalID}';`
	);

	await login(SUPPORTER_EMAIL, page, context);
	await page.goto(`/venues/proposal/${proposalID}`);
	await page.waitForLoadState('networkidle');

	const message = `support reason ${Date.now()}`;
	await page.getByTestId('proposal-support-message').fill(message);
	await page.getByTestId('proposal-support-submit').click();

	await expect
		.poll(() =>
			sql(
				`select message from public.supporters where scholarid = '${supporterID}' and proposalid = '${proposalID}';`
			)
		)
		.toBe(message);
});

test('steward edits proposal title, census, and editors', async ({ page, context }) => {
	const initialTitle = `Edit-test ${Date.now()}`;
	const proposalID = seedPendingProposal(
		initialTitle,
		[APPROVAL_MINTER_EMAIL],
		[STEWARD_EMAIL]
	);

	await login(STEWARD_EMAIL, page, context);
	await page.goto(`/venues/proposal/${proposalID}`);
	await page.waitForLoadState('networkidle');

	// Expand the steward Settings card so the edit fields render.
	await page.getByTestId('proposal-steward-card').click();

	// Title
	const newTitle = `${initialTitle} edited`;
	await page.getByTestId('proposal-title-toggle').click();
	const titleField = page.getByTestId('proposal-title');
	await titleField.fill(newTitle);
	await titleField.press('Enter');
	await expect
		.poll(() => sql(`select title from public.proposals where id = '${proposalID}';`))
		.toBe(newTitle);

	// Census
	await page.getByTestId('proposal-census-toggle').click();
	const censusField = page.getByTestId('proposal-census');
	await censusField.fill('999');
	await censusField.press('Enter');
	await expect
		.poll(() => sql(`select census from public.proposals where id = '${proposalID}';`))
		.toBe('999');

	// Editors — replace with a new editor email.
	await page.getByTestId('proposal-editors-toggle').click();
	const editorsField = page.getByTestId('proposal-editors');
	await editorsField.fill('alice@example.edu, bob@example.edu');
	await editorsField.press('Enter');
	await expect
		.poll(() => sql(`select editors from public.proposals where id = '${proposalID}';`))
		.toBe('{alice@example.edu,bob@example.edu}');
});

test('steward approves a proposal; the live venue becomes reachable at /venue/[id]', async ({
	page,
	context
}) => {
	// The approval flow looks up scholars by email, so editors and minters
	// must be existing scholars. Use the steward as the editor, and
	// author2 as the minter (different scholar, satisfies no_minter_admins).
	const title = `Approve-test ${Date.now()}`;
	const proposalID = seedPendingProposal(title, [STEWARD_EMAIL], [APPROVAL_MINTER_EMAIL]);

	await login(STEWARD_EMAIL, page, context);
	await page.goto(`/venues/proposal/${proposalID}`);
	await page.waitForLoadState('networkidle');

	await page.getByTestId('proposal-steward-card').click();

	// Approve is a confirm button — click once for confirm mode, again to commit.
	await page.getByTestId('proposal-approve').click();
	await page.getByTestId('proposal-approve').click();

	// On success the steward is redirected to /venues, and the proposal now
	// has a non-null venue column pointing at the newly-created venue.
	await page.waitForURL(/\/venues$/);
	const venueID = sql(`select venue from public.proposals where id = '${proposalID}';`);
	expect(venueID).toMatch(/^[0-9a-f-]+$/);

	// The live venue is reachable.
	await page.goto(`/venue/${venueID}`);
	await expect(page.getByText(title).first()).toBeVisible();
});

test('steward deletes a proposal; it disappears from /venues', async ({ page, context }) => {
	const title = `Delete-test ${Date.now()}`;
	const proposalID = seedPendingProposal(title, [STEWARD_EMAIL], [APPROVAL_MINTER_EMAIL]);

	await login(STEWARD_EMAIL, page, context);
	await page.goto(`/venues/proposal/${proposalID}`);
	await page.waitForLoadState('networkidle');

	await page.getByTestId('proposal-steward-card').click();

	// Delete is a confirm button (warn label "Delete this proposal forever?").
	await page.getByTestId('proposal-delete').click();
	await page.getByTestId('proposal-delete').click();

	// The handler navigates to /venues on success.
	await page.waitForURL(/\/venues$/);

	// The proposal no longer exists in the DB.
	const remaining = sql(`select count(*) from public.proposals where id = '${proposalID}';`);
	expect(remaining).toBe('0');

	// And it doesn't appear in the proposals list on /venues.
	await expect(page.getByText(title)).toHaveCount(0);
});
