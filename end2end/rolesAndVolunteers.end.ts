import { execSync } from 'child_process';
import { expect, test } from '@playwright/test';
import { login, logout } from '../src/routes/login';

const VENUE_ID = 'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6';
const EDITOR_EMAIL = 'editor@uni.edu';
const VOLUNTEER_EMAIL = 'r1@uni.edu'; // already a Reviewer in the seed
const FRESH_SCHOLAR_EMAIL = 'author1@uni.edu'; // no volunteer records in the seed
const INVITEE_EMAIL = 'author2@uni.edu';
const INVITEE_ORCID = '0000-0001-2345-6795';

function sql(statement: string): string {
	return execSync(
		`docker exec supabase_db_reciprocalapp psql -U postgres -d postgres -t -A -q -c ${JSON.stringify(statement)}`,
		{ encoding: 'utf-8' }
	).trim();
}

test('editor creates a role, edits its description, and deletes it', async ({ page, context }) => {
	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/settings`);
	await page.waitForLoadState('networkidle');

	const roleName = `e2e-role-${Date.now()}`;

	// Create
	await page.getByTestId('new-role-name').fill(roleName);
	await page.getByTestId('create-role-button').click();
	await expect
		.poll(() =>
			Number(
				sql(
					`select count(*) from public.roles where venueid = '${VENUE_ID}' and name = '${roleName}';`
				)
			)
		)
		.toBe(1);

	// Wait for the new role's card to appear, then expand the inner admin
	// settings card; the description editor and delete button live inside it.
	// (The outer role card auto-expands for admins, so we don't click it.)
	await page.getByTestId(`role-${roleName}`).waitFor();
	await page.getByTestId(`role-settings-${roleName}`).click();

	// Edit description. Wait for the toggle to be ready before clicking, then
	// fill and press Enter to commit (equivalent to clicking save again, but
	// avoids a class of timing issues where the second toggle click races
	// the bind:text propagation).
	const description = `Built by e2e at ${Date.now()}`;
	const descriptionToggle = page.getByTestId(`role-description-${roleName}-toggle`);
	await descriptionToggle.waitFor();
	await descriptionToggle.click();
	const descriptionField = page.getByTestId(`role-description-${roleName}`);
	await descriptionField.fill(description);
	await descriptionField.press('Enter');
	await expect
		.poll(() =>
			sql(
				`select description from public.roles where venueid = '${VENUE_ID}' and name = '${roleName}';`
			)
		)
		.toBe(description);

	// Delete (confirm button: click once to enter confirm mode, again to confirm).
	await page.getByTestId(`role-delete-${roleName}`).click();
	await page.getByTestId(`role-delete-${roleName}`).click();
	await expect
		.poll(() =>
			Number(
				sql(
					`select count(*) from public.roles where venueid = '${VENUE_ID}' and name = '${roleName}';`
				)
			)
		)
		.toBe(0);
});

test('editor invites a scholar to an invite-only role by ORCID', async ({ page, context }) => {
	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/settings`);
	await page.waitForLoadState('networkidle');

	const inviteeID = sql(`select id from public.scholars where orcid = '${INVITEE_ORCID}';`);

	// The Editor role is invite-only in the seed; expand it to reveal the
	// invite form (which is admin-only).
	await page.getByTestId('role-Editor').click();

	// Clear any prior volunteer record for this scholar+role so the test can
	// re-run without colliding with createVolunteer's "AlreadyVolunteered" guard.
	sql(
		`delete from public.volunteers where scholarid = '${inviteeID}' and roleid in (select id from public.roles where venueid = '${VENUE_ID}' and name = 'Editor');`
	);

	await page.getByTestId('role-invite-field-Editor').fill(INVITEE_ORCID);
	await page.getByTestId('role-invite-button-Editor').click();

	// A volunteer record now exists for the invitee on the Editor role,
	// in the 'invited' state.
	await expect
		.poll(() =>
			sql(
				`select accepted::text from public.volunteers v join public.roles r on r.id = v.roleid where v.scholarid = '${inviteeID}' and r.venueid = '${VENUE_ID}' and r.name = 'Editor';`
			)
		)
		.toBe('invited');
});

test('editor invites a scholar to an invite-only role by email', async ({ page, context }) => {
	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/settings`);
	await page.waitForLoadState('networkidle');

	const inviteeID = sql(`select id from public.scholars where email = '${INVITEE_EMAIL}';`);

	// Use the Associate Editor role (also invite-only) so this test doesn't
	// collide with the by-ORCID test above.
	await page.getByTestId('role-Associate Editor').click();

	sql(
		`delete from public.volunteers where scholarid = '${inviteeID}' and roleid in (select id from public.roles where venueid = '${VENUE_ID}' and name = 'Associate Editor');`
	);

	await page.getByTestId('role-invite-field-Associate Editor').fill(INVITEE_EMAIL);
	await page.getByTestId('role-invite-button-Associate Editor').click();

	await expect
		.poll(() =>
			sql(
				`select accepted::text from public.volunteers v join public.roles r on r.id = v.roleid where v.scholarid = '${inviteeID}' and r.venueid = '${VENUE_ID}' and r.name = 'Associate Editor';`
			)
		)
		.toBe('invited');
});

test('an invited scholar declines the invitation from the role card', async ({
	page,
	context
}) => {
	const inviteeID = sql(`select id from public.scholars where email = '${INVITEE_EMAIL}';`);

	// Reset prior state so this test can re-run cleanly.
	sql(
		`delete from public.volunteers where scholarid = '${inviteeID}' and roleid in (select id from public.roles where venueid = '${VENUE_ID}' and name = 'Editor');`
	);

	// Editor invites the scholar to the invite-only Editor role.
	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/settings`);
	await page.waitForLoadState('networkidle');
	await page.getByTestId('role-Editor').click();
	await page.getByTestId('role-invite-field-Editor').fill(INVITEE_EMAIL);
	await page.getByTestId('role-invite-button-Editor').click();
	await expect
		.poll(() =>
			sql(
				`select accepted::text from public.volunteers v join public.roles r on r.id = v.roleid where v.scholarid = '${inviteeID}' and r.venueid = '${VENUE_ID}' and r.name = 'Editor';`
			)
		)
		.toBe('invited');

	// Swap to the invitee and visit the venue page. Invite-only role cards with
	// a pending invitation for the viewer auto-expand, so the decline button is
	// directly clickable without first expanding. Dismiss the invite success
	// toast(s) first — they intercept clicks on the logout button.
	const dismissButtons = page.locator('[data-testid="feedback-success"] button');
	while ((await dismissButtons.count()) > 0) {
		await dismissButtons.first().click();
	}
	await logout(page);
	await login(INVITEE_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}`);
	await page.waitForLoadState('networkidle');

	// Decline is a confirm button: first click enters confirm mode, second
	// commits. Scope to the Editor card — earlier tests in this file may have
	// left author2 with a pending invite on Associate Editor too.
	const decline = page.getByTestId('role-Editor').getByTestId('volunteer-decline-invite');
	await decline.click();
	await decline.click();

	await expect
		.poll(() =>
			sql(
				`select accepted::text from public.volunteers v join public.roles r on r.id = v.roleid where v.scholarid = '${inviteeID}' and r.venueid = '${VENUE_ID}' and r.name = 'Editor';`
			)
		)
		.toBe('declined');
});

test('an active volunteer updates their expertise', async ({ page, context }) => {
	await login(VOLUNTEER_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}`);
	await page.waitForLoadState('networkidle');

	// Reviewer is the only role r1 holds and it's not invite-only, so its
	// card is expanded by default.
	const newExpertise = `e2e expertise ${Date.now()}`;
	await page.getByTestId('volunteer-expertise-toggle').click();
	await page.getByTestId('volunteer-expertise').fill(newExpertise);
	await page.getByTestId('volunteer-expertise-toggle').click();

	await expect
		.poll(() =>
			sql(
				`select expertise from public.volunteers v join public.roles r on r.id = v.roleid join public.scholars s on s.id = v.scholarid where s.email = '${VOLUNTEER_EMAIL}' and r.name = 'Reviewer' and r.venueid = '${VENUE_ID}';`
			)
		)
		.toBe(newExpertise);
});

test('volunteer stops and re-volunteers; welcome tokens are minted only once', async ({
	page,
	context
}) => {
	const scholarID = sql(`select id from public.scholars where email = '${FRESH_SCHOLAR_EMAIL}';`);

	// Reset state: ensure FRESH_SCHOLAR has no prior volunteer records anywhere
	// (so welcomeVolunteer's "first time" guard fires on the volunteer click)
	// and no prior welcome transactions for them.
	sql(`delete from public.volunteers where scholarid = '${scholarID}';`);
	sql(
		`delete from public.transactions where to_scholar = '${scholarID}' and purpose = 'Welcome tokens for volunteering';`
	);

	await login(FRESH_SCHOLAR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}`);
	await page.waitForLoadState('networkidle');

	// Volunteer for the (non-invite-only) Reviewer role.
	await page.getByTestId('volunteer-for-role').click();
	await expect(page.getByTestId('volunteered-for-role')).toBeVisible();

	// Welcome-token transaction count after first volunteer.
	const welcomeAfterFirst = Number(
		sql(
			`select count(*) from public.transactions where to_scholar = '${scholarID}' and purpose = 'Welcome tokens for volunteering';`
		)
	);
	expect(welcomeAfterFirst).toBe(1);

	// Stop volunteering — the seed's "Stop..." button is the volunteered-for-role
	// testid (it's the same Button rendered when active).
	await page.getByTestId('volunteered-for-role').click();
	await expect(page.getByTestId('volunteer-resume')).toBeVisible();

	// Re-volunteer via Resume — this calls updateVolunteerActive(true), which
	// must not trigger another welcomeVolunteer call.
	await page.getByTestId('volunteer-resume').click();
	await expect(page.getByTestId('volunteered-for-role')).toBeVisible();

	const welcomeAfterResume = Number(
		sql(
			`select count(*) from public.transactions where to_scholar = '${scholarID}' and purpose = 'Welcome tokens for volunteering';`
		)
	);
	expect(welcomeAfterResume).toBe(1);
});

test('editor exports volunteers as CSV with name, email, ORCID, role, expertise, active', async ({
	page,
	context
}) => {
	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/volunteers`);
	await page.waitForLoadState('networkidle');

	const downloadPromise = page.waitForEvent('download');
	await page.getByTestId('volunteer-export-csv').click();
	const download = await downloadPromise;

	const csvPath = await download.path();
	const fs = await import('fs');
	const csv = fs.readFileSync(csvPath, 'utf-8');

	// Header includes every required column.
	const header = csv.split('\n', 1)[0];
	for (const column of ['Name', 'Email', 'ORCID', 'Role', 'Expertise', 'Active']) {
		expect(header).toContain(column);
	}

	// Body has at least one volunteer row that includes a seeded scholar's
	// email. The seed always has the editor as the venue's Editor volunteer.
	expect(csv).toContain(EDITOR_EMAIL);

	// Active column carries Yes/No values, not raw booleans.
	expect(csv).toMatch(/"(Yes|No)"/);
});

test('volunteer filter on /venue/[id]/volunteers narrows the table by name, email, or expertise', async ({
	page,
	context
}) => {
	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/volunteers`);
	await page.waitForLoadState('networkidle');

	// Without a filter, multiple Reviewer rows are visible (r1..r5).
	const reviewerRowsUnfiltered = await page
		.locator('tr[data-testid^="volunteer-row-2-"]')
		.count();
	expect(reviewerRowsUnfiltered).toBeGreaterThan(1);

	// Set a filter that uniquely picks out r1 by name (Rigor Russ).
	await page.getByTestId('volunteer-filter').fill('Rigor');

	await expect
		.poll(async () => page.locator('tr[data-testid^="volunteer-row-2-"]').count())
		.toBe(1);

	// Clear the filter; rows return.
	await page.getByTestId('volunteer-filter').fill('');
	await expect
		.poll(async () => page.locator('tr[data-testid^="volunteer-row-2-"]').count())
		.toBeGreaterThan(1);
});
