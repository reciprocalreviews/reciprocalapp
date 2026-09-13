import { expect, test } from '@playwright/test';
import { login, logout } from '../src/routes/login';
import { SEED, sql } from './test-utils';

/**
 * The call for bids: a venue's editor writes a short personal note to the volunteers of one
 * biddable role, asking them to come and bid.
 *
 * This is the only mail RR sends whose prose a person writes, so what is checked here is the
 * shape that keeps it from being a way to mail anybody anything — who is offered the form, who
 * actually receives the message, that replies come back to the sender, and that the body is
 * left to the registry rather than written by the client.
 *
 * There is no edge runtime in the e2e run, so nothing is delivered and every send fails
 * delivery. Assertions read `public.emails` directly, as the new-volunteer notice test does.
 */

const VENUE_ID = SEED.venue;
const VENUE_PATH = SEED.venuePath;
const ROLE_ID = SEED.roles.reviewer;
const EDITOR_EMAIL = SEED.scholars.editor.email;
const EDITOR_ID = SEED.scholars.editor.id;
/** An accepted Reviewer in the seed, and so a recipient. */
const REVIEWER_EMAIL = SEED.scholars.r1.email;
/** Another accepted Reviewer, used as the one who has opted out. */
const MUTED_ID = SEED.scholars.r2.id;
const MUTED_EMAIL = SEED.scholars.r2.email;

/** The seed's Reviewer role is biddable; the form only appears on roles that are. */
const ROLE_NAME = 'Reviewer';

/** `rgb(0, 114, 132)` as `#007284`, so a computed colour can be compared with a palette hex. */
function hexOf(rgb: string): string {
	const [r, g, b] = rgb.match(/\d+/g)!.map(Number);
	return '#' + [r, g, b].map((n) => n.toString(16).padStart(2, '0')).join('');
}

function clean() {
	sql(`delete from public.emails where event = 'CallForBids' and venue = '${VENUE_ID}';`);
	sql(`delete from public.notification_settings where event = 'CallForBids';`);
}

test('an editor asks a biddable role to bid, and only the eligible are written to', async ({
	page,
	context
}) => {
	clean();

	// One volunteer has turned the notice off. They must be neither counted in the form's
	// recipient total nor written to — the count and the send share one predicate precisely so
	// the number an editor is shown is the number that goes out.
	sql(
		`insert into public.notification_settings (scholar, event, enabled) values ('${MUTED_ID}', 'CallForBids', false) on conflict (scholar, event) do update set enabled = false;`
	);

	const note = `Bids are thin this cycle — please take a look. ${Date.now()}`;

	const recipients = () =>
		sql(
			`select coalesce(string_agg(email, ',' order by email), '') from public.emails where event = 'CallForBids' and venue = '${VENUE_ID}';`
		);

	try {
		await login(EDITOR_EMAIL, page, context);
		await page.goto(`/venue/${VENUE_PATH}`);
		await page.waitForLoadState('networkidle');

		// The role cards are collapsed until opened.
		await page.getByTestId(`role-${ROLE_NAME}`).click();

		const field = page.getByTestId(`call-for-bids-note-${ROLE_NAME}`);
		await expect(field).toBeVisible();
		await field.fill(note);

		// A confirm button: the mail goes out at once and cannot be recalled, so the first
		// click asks and the second sends.
		await page.getByTestId(`call-for-bids-send-${ROLE_NAME}`).click();
		await page.getByTestId(`call-for-bids-send-${ROLE_NAME}`).click();

		await expect.poll(recipients).toContain(REVIEWER_EMAIL);

		// ONE banner, however many people were emailed. The seed's Reviewer role has more than
		// the three that are shown individually, so this send used to post a bar per recipient
		// into the sticky header — enough to push the page below the fold and cover the nav.
		const banners = page.getByTestId('feedback-success');
		await expect(banners).toHaveCount(1);
		// It names somebody and counts the rest, so the difference between who was asked and who
		// was actually reachable is still legible.
		await expect(banners.first()).toContainText('others');

		// And it is painted as good news. Success used to share a CSS rule with the beta notice
		// and so arrived in the error colour, which nothing caught because nothing looked. Read
		// against the palette rather than a hardcoded hex, so rebranding does not break this.
		const [banner, salient] = await page.evaluate(() => {
			const el = document.querySelector('[data-testid="feedback-success"]')!;
			return [
				getComputedStyle(el).backgroundColor,
				getComputedStyle(document.documentElement).getPropertyValue('--salient-color').trim()
			];
		});
		expect(hexOf(banner)).toBe(salient.toLowerCase());

		const got = recipients();
		// The sender is left off their own call, and the opted-out volunteer is skipped.
		expect(got).not.toContain(EDITOR_EMAIL);
		expect(got).not.toContain(MUTED_EMAIL);

		// One private copy per recipient. These are reviewers who must not learn each other's
		// addresses, so unlike the new-volunteer notice nothing is Cc'd.
		expect(
			sql(
				`select count(*) from public.emails where event = 'CallForBids' and venue = '${VENUE_ID}' and cc is not null;`
			)
		).toBe('0');

		// Replies reach the editor who wrote it, not the steward inbox.
		expect(
			sql(
				`select distinct reply_to from public.emails where event = 'CallForBids' and venue = '${VENUE_ID}';`
			)
		).toBe(EDITOR_EMAIL);

		// The client supplied a note, not a body: subject and message stay null so the registry
		// renders the mail at send time, and the note arrives as one of six arguments.
		expect(
			sql(
				`select count(*) from public.emails where event = 'CallForBids' and venue = '${VENUE_ID}' and (subject is not null or message is not null);`
			)
		).toBe('0');
		expect(
			sql(
				`select distinct jsonb_array_length(args) from public.emails where event = 'CallForBids' and venue = '${VENUE_ID}';`
			)
		).toBe('6');
		expect(
			sql(
				`select distinct args->>3 from public.emails where event = 'CallForBids' and venue = '${VENUE_ID}';`
			)
		).toBe(note);

		// Attributable, which is the other half of allowing prose at all.
		expect(
			sql(
				`select distinct sender::text from public.emails where event = 'CallForBids' and venue = '${VENUE_ID}';`
			)
		).toBe(EDITOR_ID);
	} finally {
		clean();
	}
	await logout(page);
});

test('a plain volunteer is not offered the form', async ({ page, context }) => {
	// An affordance check, not an authorization one — queue_call_for_bids refuses this scholar
	// whatever the interface shows, and the pgTAP suite is where that is proven. What is worth
	// asserting here is that a reviewer is not shown a control that would fail if they used it.
	await login(REVIEWER_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_PATH}`);
	await page.waitForLoadState('networkidle');
	await page.getByTestId(`role-${ROLE_NAME}`).click();

	// The card is open — its volunteer controls are there — but the compose field is not.
	await expect(page.getByTestId('volunteer-for-role').or(page.getByTestId('stop-volunteering')))
		.toBeVisible;
	await expect(page.getByTestId(`call-for-bids-note-${ROLE_NAME}`)).toHaveCount(0);

	await logout(page);
});

test('the form is absent on a role that cannot be bid on', async ({ page, context }) => {
	// A nudge to bid, sent to people the submissions page will not show bid buttons to, is a
	// message nobody can act on, so the form is not offered at all.
	const wasBiddable = sql(`select biddable from public.roles where id = '${ROLE_ID}';`);
	sql(`update public.roles set biddable = false where id = '${ROLE_ID}';`);
	try {
		await login(EDITOR_EMAIL, page, context);
		await page.goto(`/venue/${VENUE_PATH}`);
		await page.waitForLoadState('networkidle');
		await page.getByTestId(`role-${ROLE_NAME}`).click();
		await expect(page.getByTestId(`call-for-bids-note-${ROLE_NAME}`)).toHaveCount(0);
	} finally {
		sql(`update public.roles set biddable = ${wasBiddable === 't'} where id = '${ROLE_ID}';`);
	}
	await logout(page);
});
