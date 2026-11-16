import { test, expect } from '@playwright/test';
import { logout } from '../src/routes/login';
import { loginAndGoto, SEED, sql } from './test-utils';

const PAGE = `/venue/${SEED.venuePath}/submissions/assign`;

test('an editor assigns a pasted list in one confirmation', async ({ page, context }) => {
	const stamp = Date.now();
	const byName = `LIST-NAME-${stamp}`;
	const byEmail = `LIST-EMAIL-${stamp}`;
	const unknown = `LIST-UNKNOWN-${stamp}`;
	const flipped = `LIST-FLIPPED-${stamp}`;
	const missing = `LIST-MISSING-${stamp}`;
	const unknownName = `Nobody Here ${stamp}`;
	const type = sql(
		`select id from public.submission_types where venue = '${SEED.venue}' order by id limit 1;`
	);
	const ae = sql(
		`select id from public.roles where venueid = '${SEED.venue}' and name = 'Associate Editor';`
	);
	const yure = sql(`select id from public.scholars where email = 't.yure@uni.edu';`);
	const access = sql(`select id from public.scholars where email = 'o.access@uni.edu';`);
	const batical = sql(`select id from public.scholars where email = 's.batical@uni.edu';`);
	for (const id of [byName, byEmail, unknown, flipped])
		sql(
			`insert into public.submissions (venue, externalid, submission_type, authors, payments, transactions, title) values ('${SEED.venue}', '${id}', '${type}', array['${SEED.scholars.author1.id}']::uuid[], array[0], array['00000000-0000-0000-0000-000000000000']::uuid[], 'Paper ${id}');`
		);
	const started = sql(`select now();`);

	try {
		await loginAndGoto(page, context, SEED.scholars.editor.email, PAGE, 'assign-list-text');
		await page.waitForLoadState('networkidle');
		await expect(page.getByRole('heading', { name: 'Bulk assign' })).toBeVisible();
		await page.getByTestId('assign-list-role').selectOption({ label: 'Associate Editor' });
		await expect(page.getByTestId('assign-list-role')).toHaveValue(ae);
		// Two spreadsheet columns, a typed line with an email, a name nobody has, a surname
		// alone written before its ID with only a space between, and a manuscript the venue
		// doesn't have.
		await page
			.getByTestId('assign-list-text')
			.fill(
				[
					`${byName}\tYure, Ten`,
					`${byEmail}, o.access@uni.edu`,
					`${unknown}\t${unknownName}`,
					`Batical ${flipped}`,
					`${missing}\tSab Batical`
				].join('\n')
			);
		await page.getByTestId('assign-list-check').click();

		await expect(page.getByTestId('assign-list-summary')).toHaveText(
			'3 ready to assign, 1 to keep for matching later, 1 will be skipped.'
		);
		await expect(page.getByTestId('assign-list-row-0-status')).toHaveText('ready');
		await expect(page.getByTestId('assign-list-row-1-status')).toHaveText('ready');
		await expect(page.getByTestId('assign-list-row-2-status')).toHaveText(
			'kept for matching later'
		);
		await expect(page.getByTestId('assign-list-row-3-status')).toHaveText('ready');
		await expect(page.getByTestId('assign-list-row-4-status')).toHaveText('no such manuscript');

		// Checking wrote nothing.
		expect(
			sql(
				`select count(*) from public.assignments a join public.submissions s on s.id = a.submission where s.externalid in ('${byName}', '${byEmail}');`
			)
		).toBe('0');

		// Seating people asks first whether they agreed; the same button confirms.
		const assign = page.getByTestId('assign-list-assign');
		await expect(assign).toHaveText('Assign 4…');
		await assign.click();
		await expect(assign).toHaveText('Everyone named agreed, assign 4');
		await assign.click();

		await expect(page.getByTestId('assign-list-result')).toContainText(
			'Assigned 3, kept 1 for matching later, skipped 1.'
		);
		await expect(page.getByTestId('assign-list-row-0-status')).toHaveText('assigned');

		expect(
			sql(
				`select string_agg(s.externalid || ':' || a.scholar, ',' order by s.externalid) from public.assignments a join public.submissions s on s.id = a.submission where s.externalid in ('${byName}', '${byEmail}', '${flipped}') and a.role = '${ae}' and a.approved;`
			)
		).toBe(`${byEmail}:${access},${flipped}:${batical},${byName}:${yure}`);
		expect(
			sql(
				`select u.name from public.unmatched_assignments u join public.submissions s on s.id = u.submission where s.externalid = '${unknown}';`
			)
		).toBe(unknownName);
		// One digest each.
		await expect
			.poll(() =>
				sql(
					`select count(*) from public.emails where event = 'SubmissionsAssigned' and scholar in ('${yure}', '${access}', '${batical}') and time_sent >= '${started}';`
				)
			)
			.toBe('3');

		await logout(page);
	} finally {
		sql(
			`delete from public.submissions where externalid in ('${byName}', '${byEmail}', '${unknown}', '${flipped}');`
		);
	}
});

test('someone who neither administers nor edits the venue is told they cannot', async ({
	page,
	context
}) => {
	await loginAndGoto(page, context, SEED.scholars.author1.email, PAGE, 'assign-list-not-allowed');
	await expect(page.getByTestId('assign-list-text')).toHaveCount(0);
	await logout(page);
});
