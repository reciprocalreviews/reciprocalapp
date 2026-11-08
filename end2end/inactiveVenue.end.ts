import { expect, test } from '@playwright/test';
import { login } from '../src/routes/login';
import { SEED, sql } from './test-utils';

// The seed's closed venue, seen by its admin (the seeded editor). An inactive venue takes no
// new work (#42), so its admin is told it is inactive and is offered nothing that would start
// any: no new submission, no import, no volunteering. The database refuses all of it too
// (supabase/tests/rpc/inactive_venue.sql); this checks the interface does not offer it.
const VENUE_PATH = SEED.inactiveVenue.path;

test.describe('the admin of a closed venue', () => {
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
});

// Closing a venue does not strand the work already under way there (#42). Anyone with an
// approved, unfinished assignment on a submission still under review, or who wrote one, gets
// in to finish it; everyone else still reaches the closed page. The seed's closed venue has
// no work, so this gives it some, opening it just long enough to (a closed venue refuses new
// submissions, from fixtures too), and takes it all away again afterwards.
test.describe('participants of a closed venue', () => {
	const VENUE = SEED.inactiveVenue.id;
	const ROLE = '5e8a0c30-bd41-11f1-9b6e-3f0c2a7d4e51';
	const TYPE = '5e8a0c31-bd41-11f1-9b6e-3f0c2a7d4e51';
	const SUBMISSION = '5e8a0c32-bd41-11f1-9b6e-3f0c2a7d4e51';
	const ASSIGNMENT = '5e8a0c33-bd41-11f1-9b6e-3f0c2a7d4e51';
	const REVIEWER = SEED.scholars.r1;
	const AUTHOR = SEED.scholars.author1;

	// One line per statement, joined with spaces: `sql()` passes its argument through
	// JSON.stringify, which turns a newline into a literal `\n` that psql reads as a
	// meta-command.
	test.beforeAll(() => {
		sql(
			[
				`update public.venues set inactive = null where id = '${VENUE}';`,
				`insert into public.roles (id, venueid, name, priority, invited) values ('${ROLE}', '${VENUE}', 'Referee', 1, false);`,
				`insert into public.submission_types (id, venue, name) values ('${TYPE}', '${VENUE}', 'Paper');`,
				`insert into public.submissions (id, venue, externalid, submission_type, authors, payments, transactions) values ('${SUBMISSION}', '${VENUE}', 'SOR-1', '${TYPE}', array['${AUTHOR.id}']::uuid[], array[0], array['00000000-0000-0000-0000-000000000000']::uuid[]);`,
				`insert into public.assignments (id, venue, submission, scholar, role, approved) values ('${ASSIGNMENT}', '${VENUE}', '${SUBMISSION}', '${REVIEWER.id}', '${ROLE}', true);`,
				`update public.venues set inactive = '${SEED.inactiveVenue.message}' where id = '${VENUE}';`
			].join(' ')
		);
	});

	test.afterAll(() => {
		sql(
			[
				`delete from public.assignments where id = '${ASSIGNMENT}';`,
				`delete from public.submissions where id = '${SUBMISSION}';`,
				`delete from public.submission_types where id = '${TYPE}';`,
				`delete from public.roles where id = '${ROLE}';`
			].join(' ')
		);
	});

	const participants: { who: string; email: string }[] = [
		{ who: 'a reviewer with unfinished work', email: REVIEWER.email },
		{ who: 'an author of a submission under review', email: AUTHOR.email }
	];
	for (const { who, email } of participants) {
		test(`${who} gets in, and is told the venue is inactive`, async ({ page, context }) => {
			await login(email, page, context);
			await page.goto(`/venue/${VENUE_PATH}`);
			await page.waitForLoadState('networkidle');

			await expect(page.getByTestId('venue-inactive-participant')).toBeVisible();
			await expect(page.getByTestId('venue-bar-inactive')).toBeVisible();
			await expect(page.getByTestId('venue-inactive-notice')).toHaveCount(0);
			await expect(page.getByTestId('venue-new-submission')).toHaveCount(0);
		});
	}

	test('someone with no work there still reaches the closed page', async ({ page, context }) => {
		await login(SEED.scholars.r2.email, page, context);
		await page.goto(`/venue/${VENUE_PATH}`);
		await page.waitForLoadState('networkidle');

		await expect(page.getByTestId('venue-inactive-notice')).toBeVisible();
	});
});
