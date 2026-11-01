import { expect, test } from '@playwright/test';
import { login, logout } from '../src/routes/login';
import { SEED, sql } from './test-utils';

// Adding people to a role once they have agreed, without an invitation for them to
// accept: from a role's card, and from the unmatched page, where it also matches them.
//
// Both use seeded reviewers, who already hold a role at the venue, so no welcome grant
// changes a balance another test reads. Each removes the record it made, because a
// second Associate Editor is visible to every test that lists the role.

const VENUE_ID = SEED.venue;
const VENUE_PATH = SEED.venuePath;
const AE_ROLE = 'Associate Editor';

function clearAE(scholar: string) {
	sql(
		`delete from public.volunteers where scholarid = '${scholar}' and roleid in (select id from public.roles where venueid = '${VENUE_ID}' and name = '${AE_ROLE}');`
	);
}

function aeStatus(scholar: string) {
	return sql(
		`select v.accepted::text || '/' || v.active::text from public.volunteers v join public.roles r on r.id = v.roleid where v.scholarid = '${scholar}' and r.venueid = '${VENUE_ID}' and r.name = '${AE_ROLE}';`
	);
}

test('an admin adds someone who already agreed to a role', async ({ page, context }) => {
	const added = SEED.scholars.r3;
	clearAE(added.id);
	try {
		await login(SEED.scholars.editor.email, page, context);
		await page.goto(`/venue/${VENUE_PATH}/settings`);
		await page.waitForLoadState('networkidle');
		await page.getByTestId(`role-${AE_ROLE}`).click();

		await page.getByTestId(`role-invite-field-${AE_ROLE}`).fill(added.email);
		await page.getByTestId(`role-invite-match-${AE_ROLE}-${added.id}`).click();
		await page.getByTestId(`role-invite-agreed-${AE_ROLE}`).click();

		// A confirm button: the first click asks, the second adds.
		const button = page.getByTestId(`role-invite-button-${AE_ROLE}`);
		await expect(button).toHaveText('Add…');
		await button.click();
		await button.click();

		await expect.poll(() => aeStatus(added.id)).toBe('accepted/true');
		// Told they were added, and not sent an invitation to answer.
		await expect
			.poll(() =>
				sql(
					`select string_agg(event, ',' order by event) from public.emails where scholar = '${added.id}' and event in ('RoleEnrolled', 'RoleInvite') and time_sent > now() - interval '1 minute';`
				)
			)
			.toBe('RoleEnrolled');
		await logout(page);
	} finally {
		clearAE(added.id);
	}
});

test('an admin adds an imported name to its role and matches it in one step', async ({
	page,
	context
}) => {
	const person = SEED.scholars.r4;
	// Surname first, so it is the import's spelling and not the profile's that is matched.
	const [given, family] = person.name.split(' ');
	const imported = `${family}, ${given}`;
	const external = `import-agreed-${Date.now()}`;
	clearAE(person.id);
	try {
		await login(SEED.scholars.editor.email, page, context);

		await page.goto(`/venue/${VENUE_PATH}/submissions/import`);
		await page.waitForLoadState('networkidle');
		await page
			.getByTestId('bulk-import-paste')
			.fill(`title,externalid,associate editor\nAgreed paper,${external},"${imported}"`);
		await page.getByTestId('bulk-import-parse').click();
		const aeRole = sql(
			`select id from public.roles where venueid = '${VENUE_ID}' and name = '${AE_ROLE}';`
		);
		await page.getByTestId(`role-column-${aeRole}`).selectOption({ label: 'associate editor' });
		// Naming people asks first whether they agreed; the same button confirms.
		await page.getByTestId('bulk-import-submit').click();
		await page.getByTestId('bulk-import-submit').click();
		await page.waitForURL(`**/venue/${VENUE_PATH}/submissions`);

		await page.goto(`/venue/${VENUE_PATH}/submissions/unmatched`);
		await page.waitForLoadState('networkidle');
		const row = page.locator('tr.group', { hasText: imported });
		await row.locator('[data-testid$="-add-find"]').click();

		const add = row.locator(`[data-testid$="-add-add-${person.id}"]`);
		await expect(add).toHaveText(`Add ${person.name} as ${AE_ROLE} and match…`);
		await add.click();
		await add.click();

		await expect(row).toHaveCount(0);
		await expect.poll(() => aeStatus(person.id)).toBe('accepted/true');
		await expect
			.poll(() =>
				sql(
					`select count(*) from public.assignments a join public.submissions s on s.id = a.submission where s.externalid = '${external}' and a.scholar = '${person.id}' and a.approved;`
				)
			)
			.toBe('1');
		await logout(page);
	} finally {
		clearAE(person.id);
	}
});

test('an editor-in-chief who is not an admin adds someone to a role from the venue page', async ({
	page,
	context
}) => {
	// The seed's only accepted Editor is also the venue's admin, so make another one for the
	// length of this test: the point is that holding the top role is enough.
	const eic = SEED.scholars.r2;
	const added = SEED.scholars.r3;
	const editorRole = SEED.roles.editor;
	clearAE(added.id);
	sql(
		`insert into public.volunteers (scholarid, roleid, expertise, accepted, active) values ('${eic.id}', '${editorRole}', '', 'accepted', true) on conflict do nothing;`
	);
	try {
		await login(eic.email, page, context);
		await page.goto(`/venue/${VENUE_PATH}`);
		await page.waitForLoadState('networkidle');
		await page.getByTestId(`role-${AE_ROLE}`).click();

		await page.getByTestId(`role-invite-field-${AE_ROLE}`).fill(added.email);
		await page.getByTestId(`role-invite-match-${AE_ROLE}-${added.id}`).click();
		await page.getByTestId(`role-invite-agreed-${AE_ROLE}`).click();
		const button = page.getByTestId(`role-invite-button-${AE_ROLE}`);
		await button.click();
		await button.click();

		await expect.poll(() => aeStatus(added.id)).toBe('accepted/true');
		await logout(page);
	} finally {
		clearAE(added.id);
		sql(
			`delete from public.volunteers where scholarid = '${eic.id}' and roleid = '${editorRole}';`
		);
	}
});
