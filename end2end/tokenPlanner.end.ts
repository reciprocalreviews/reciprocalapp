import { expect, test, type Page } from '@playwright/test';
import { login, logout } from '../src/routes/login';
import { SEED, sql } from './test-utils';

// The token planner on the venue setup page (#57): per submission type, what a paper pays
// out to its roles against what it costs, every number editable in place.
//
// The seed's Research Article costs 10 and pays out 1 (editor) + 10 (AE) + 3 × 10
// (reviewers) = 41, so it starts out paying more than it costs. Every edit here is
// restored in `finally`: other suites hard-code the seeded cost and reviewer count, and the
// local database is not reset between runs.

const VENUE_ID = SEED.venue;
const VENUE_PATH = SEED.venuePath;
const TYPE = 'Research Article';
const REVISION = 'Research Article - Revision';

const typeID = (name: string) =>
	sql(`select id from public.submission_types where venue = '${VENUE_ID}' and name = '${name}';`);
const roleID = (name: string) =>
	sql(`select id from public.roles where venueid = '${VENUE_ID}' and name = '${name}';`);

/** Open an EditableText, replace its value, and save it. */
async function editField(page: Page, testid: string, value: string) {
	await page.getByTestId(`${testid}-toggle`).click();
	await page.getByTestId(testid).fill(value);
	await page.getByTestId(`${testid}-toggle`).click();
}

test('an admin balances a submission type in the token planner', async ({ page, context }) => {
	const cost = sql(
		`select submission_cost from public.submission_types where id = '${typeID(TYPE)}';`
	);
	const reviewer = roleID('Reviewer');
	const reviewers = sql(`select desired_assignments from public.roles where id = '${reviewer}';`);
	try {
		await login(SEED.scholars.editor.email, page, context);
		await page.goto(`/venue/${VENUE_PATH}/settings`);
		await page.waitForLoadState('networkidle');

		const status = page.getByTestId(`planner-${TYPE}-status`);
		await expect(status).toContainText(/Pays out\s*★\s*31 tokens more/);

		// Raising the cost past the 41 paid out balances it, with the surplus to the reserve.
		await editField(page, `planner-${TYPE}-cost`, '50');
		await expect
			.poll(() =>
				sql(`select submission_cost from public.submission_types where id = '${typeID(TYPE)}';`)
			)
			.toBe('50');
		await expect(status).toContainText(/Balanced.*costs\s*★\s*9 tokens more/);

		// A fourth reviewer per paper adds 10 more paid out: 51 against 50.
		await editField(page, `planner-${TYPE}-count-Reviewer`, '4');
		await expect
			.poll(() => sql(`select desired_assignments from public.roles where id = '${reviewer}';`))
			.toBe('4');
		await expect(status).toContainText(/Pays out\s*★\s*1 token more/);

		await logout(page);
	} finally {
		sql(
			`update public.submission_types set submission_cost = ${cost} where id = '${typeID(TYPE)}';`
		);
		sql(`update public.roles set desired_assignments = ${reviewers} where id = '${reviewer}';`);
	}
});

test("an admin sets and clears a role's pay in the token planner", async ({ page, context }) => {
	// The revision type pays nobody in the seed, so it costs 4 and pays out nothing.
	const revision = typeID(REVISION);
	const editor = roleID('Editor');
	const pay = () =>
		sql(
			`select coalesce(amount::text, 'null') from public.compensation where submission_type = '${revision}' and role = '${editor}';`
		);
	try {
		await login(SEED.scholars.editor.email, page, context);
		await page.goto(`/venue/${VENUE_PATH}/settings`);
		await page.waitForLoadState('networkidle');

		const status = page.getByTestId(`planner-${REVISION}-status`);
		await expect(status).toContainText(/Balanced.*costs\s*★\s*4 tokens more/);

		await editField(page, `planner-${REVISION}-pay-Editor`, '2');
		await expect.poll(pay).toBe('2');
		await expect(status).toContainText(/costs\s*★\s*2 tokens more/);

		// Emptying the field makes the role unpaid for this type again.
		await editField(page, `planner-${REVISION}-pay-Editor`, '');
		await expect.poll(pay).toBe('null');
		await expect(status).toContainText(/costs\s*★\s*4 tokens more/);

		await logout(page);
	} finally {
		sql(
			`delete from public.compensation where submission_type = '${revision}' and role = '${editor}';`
		);
	}
});
