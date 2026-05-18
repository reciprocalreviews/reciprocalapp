import { execSync } from 'child_process';
import { expect, test } from '@playwright/test';
import { login } from '../src/routes/login';

const VENUE_ID = 'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6';
const EDITOR_EMAIL = 'editor@uni.edu';
const VOLUNTEER_EMAIL = 'r1@uni.edu'; // already a Reviewer in the seed
const SUBMISSION_ID = 'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c12';

function sql(statement: string): string {
	return execSync(
		`docker exec supabase_db_reciprocalapp psql -U postgres -d postgres -t -A -q -c ${JSON.stringify(statement)}`,
		{ encoding: 'utf-8' }
	).trim();
}

function cleanupPreferenceLevels() {
	sql(`delete from public.preference_levels where venueid = '${VENUE_ID}';`);
}

test('editor adds, edits, reorders, and deletes preference levels', async ({ page, context }) => {
	cleanupPreferenceLevels();

	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/settings`);
	await page.waitForLoadState('networkidle');

	// Add two levels.
	await page.getByTestId('new-preference-level').fill('Preferred');
	await page.getByTestId('add-preference-level').click();
	await expect
		.poll(() =>
			Number(sql(`select count(*) from public.preference_levels where venueid = '${VENUE_ID}';`))
		)
		.toBe(1);

	await page.getByTestId('new-preference-level').fill('If necessary');
	await page.getByTestId('add-preference-level').click();
	await expect
		.poll(() =>
			Number(sql(`select count(*) from public.preference_levels where venueid = '${VENUE_ID}';`))
		)
		.toBe(2);

	// Verify ranks are 0,1 in insertion order.
	const initialOrder = sql(
		`select string_agg(label, '|' order by rank) from public.preference_levels where venueid = '${VENUE_ID}';`
	);
	expect(initialOrder).toBe('Preferred|If necessary');

	// Edit the rank-1 label.
	const editToggle = page.getByTestId('preference-level-1-toggle');
	await editToggle.waitFor();
	await editToggle.click();
	const field = page.getByTestId('preference-level-1');
	await field.fill('If necessary, only');
	await field.press('Enter');
	await expect
		.poll(() =>
			sql(
				`select label from public.preference_levels where venueid = '${VENUE_ID}' and rank = 1;`
			)
		)
		.toBe('If necessary, only');

	// Move the rank-1 level up (swap with rank 0). Two up-buttons exist (the
	// rank-0 one is disabled); scope to the listitem that contains the renamed
	// label so we hit the enabled one.
	await page
		.getByRole('listitem')
		.filter({ hasText: 'If necessary, only' })
		.getByRole('button', { name: 'Move this level up (toward more preferred).' })
		.click();
	await expect
		.poll(() =>
			sql(
				`select string_agg(label, '|' order by rank) from public.preference_levels where venueid = '${VENUE_ID}';`
			)
		)
		.toBe('If necessary, only|Preferred');

	// Delete both.
	cleanupPreferenceLevels();
	await expect
		.poll(() =>
			Number(sql(`select count(*) from public.preference_levels where venueid = '${VENUE_ID}';`))
		)
		.toBe(0);
});

test('volunteer sets their papers cap from the role card', async ({ page, context }) => {
	// Reset the volunteer's papers to null first so we observe the change.
	sql(
		`update public.volunteers v set papers = null from public.scholars s, public.roles r where v.scholarid = s.id and v.roleid = r.id and s.email = '${VOLUNTEER_EMAIL}' and r.name = 'Reviewer' and r.venueid = '${VENUE_ID}';`
	);

	await login(VOLUNTEER_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}`);
	await page.waitForLoadState('networkidle');

	await page.getByTestId('volunteer-papers-toggle').click();
	await page.getByTestId('volunteer-papers').fill('3');
	await page.getByTestId('volunteer-papers').press('Enter');

	await expect
		.poll(() =>
			sql(
				`select coalesce(papers::text, '') from public.volunteers v join public.scholars s on s.id = v.scholarid join public.roles r on r.id = v.roleid where s.email = '${VOLUNTEER_EMAIL}' and r.name = 'Reviewer' and r.venueid = '${VENUE_ID}';`
			)
		)
		.toBe('3');
});

test('CSV export includes the Papers cap column and value', async ({ page, context }) => {
	// Ensure r1 has a known cap so we can grep for it.
	sql(
		`update public.volunteers v set papers = 3 from public.scholars s, public.roles r where v.scholarid = s.id and v.roleid = r.id and s.email = '${VOLUNTEER_EMAIL}' and r.name = 'Reviewer' and r.venueid = '${VENUE_ID}';`
	);

	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/volunteers`);
	await page.waitForLoadState('networkidle');

	const downloadPromise = page.waitForEvent('download');
	await page.getByTestId('volunteer-export-csv').click();
	const download = await downloadPromise;
	const fs = await import('fs');
	const csv = fs.readFileSync((await download.path())!, 'utf-8');
	expect(csv.split('\n', 1)[0]).toContain('Papers cap');
	expect(csv).toContain('"3"');
});

test('editor sees bid preference label and used/cap on submission detail', async ({
	page,
	context
}) => {
	cleanupPreferenceLevels();

	// Seed a preference level for this venue.
	sql(
		`insert into public.preference_levels (venueid, label, rank) values ('${VENUE_ID}', 'Preferred', 0);`
	);

	// Find a Reviewer-role scholar who isn't currently approved on this submission,
	// then inject a pending bid for them with the Preferred preference attached.
	// We use r2 (author2@uni.edu is a different scholar entirely; r2..r5 are the
	// alternate reviewer pool from the seed). To be robust, pick a reviewer who is
	// not already assigned to SUBMISSION_ID.
	const bidderEmail = 'r2@uni.edu';
	const bidderID = sql(`select id from public.scholars where email = '${bidderEmail}';`);
	const reviewerRoleID = sql(
		`select id from public.roles where venueid = '${VENUE_ID}' and name = 'Reviewer';`
	);
	const preferenceLevelID = sql(
		`select id from public.preference_levels where venueid = '${VENUE_ID}' and label = 'Preferred';`
	);

	// Clean any prior assignments by this bidder on this submission.
	sql(
		`delete from public.assignments where submission = '${SUBMISSION_ID}' and scholar = '${bidderID}';`
	);

	// Set the bidder's papers cap to 1 so the used/cap renders.
	sql(
		`update public.volunteers set papers = 1 where scholarid = '${bidderID}' and roleid = '${reviewerRoleID}';`
	);

	// Insert the bid directly. This skips the UI bid flow (which is covered
	// indirectly by reviewerAssignment.end.ts and the createAssignment unit path).
	sql(
		`insert into public.assignments (venue, submission, scholar, role, bid, approved, preferenceid) values ('${VENUE_ID}', '${SUBMISSION_ID}', '${bidderID}', '${reviewerRoleID}', true, false, '${preferenceLevelID}');`
	);

	// Editor (ae@uni.edu is the AE for this submission per the seed) views the page.
	await login('ae@uni.edu', page, context);
	await page.goto(`/venue/${VENUE_ID}/submission/${SUBMISSION_ID}`);
	await page.waitForLoadState('networkidle');

	// The bid's preference label and used/cap indicator render.
	await expect(page.getByTestId('bid-preference-label').first()).toHaveText('Preferred');
	await expect(page.getByTestId('bid-papers-load').first()).toBeVisible();

	// Clean up so we don't leave the bid behind for other tests.
	sql(
		`delete from public.assignments where submission = '${SUBMISSION_ID}' and scholar = '${bidderID}' and bid = true;`
	);
	cleanupPreferenceLevels();
});
