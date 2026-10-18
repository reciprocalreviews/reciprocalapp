import { test, expect } from '@playwright/test';
import { login, logout } from '../src/routes/login';
import { SEED, sql } from './test-utils';

const VENUE_ID = SEED.venue;
const VENUE_PATH = SEED.venuePath;
const SUBMISSION_EXTERNAL_ID = SEED.submissions.tok001.externalId;
const SUBMISSION_ID = SEED.submissions.tok001.id;
const SUBMISSION_002 = SEED.submissions.tok002.id;
const REVIEWER_ROLE = SEED.roles.reviewer;
/** The reviewer-only scholar `filters.uniqueReviewer` picks out. */
const BIDDER_ID = SEED.scholars.r4.id;

const APPROVE_BID_TIP =
	'Accept this bid for compensation. Also assign them in your reviewing system.';
const APPROVE_ANYWAY_TIP = 'Assign this scholar despite the load warning';
const UNASSIGN_TIP = 'Remove this assignment';

test('AE assigns two reviewer bids and bidding closes', async ({ page, context }) => {
	await login('ae@uni.edu', page, context);

	// Submissions list shows the submission.
	await page.goto(`/venue/${VENUE_PATH}/submissions`);
	await expect(page.getByText(SUBMISSION_EXTERNAL_ID)).toBeVisible();

	// Open the submission detail page.
	await page.goto(`/venue/${VENUE_PATH}/submission/${SUBMISSION_ID}`);
	await page.waitForLoadState('networkidle');

	// Two pending bids waiting for assignment, plus one already-approved Reviewer
	// from the seed, producing one Unassign button.
	await expect(page.getByRole('button', { name: APPROVE_BID_TIP })).toHaveCount(2);
	await expect(page.getByRole('button', { name: UNASSIGN_TIP })).toHaveCount(1);

	// A bidder's address is there before their bid is accepted too, so the AE can ask them
	// about it first.
	await expect(page.getByTestId('assignee-email')).toHaveCount(3);
	await expect(
		page.getByTestId('assignee-email').getByRole('link', { name: SEED.scholars.r4.email })
	).toHaveAttribute('href', `mailto:${SEED.scholars.r4.email}`);
	// And their ORCID iD, for a reviewing system that invites by iD rather than address.
	await expect(page.getByTestId('assignee-orcid')).toHaveCount(3);
	await expect(
		page.getByTestId('assignee-orcid').filter({ hasText: SEED.scholars.r4.orcid })
	).toHaveAttribute('href', `https://orcid.org/${SEED.scholars.r4.orcid}`);

	// Assign the first bid; one fewer pending, one more Unassign.
	await page.getByRole('button', { name: APPROVE_BID_TIP }).first().click();
	await expect(page.getByRole('button', { name: APPROVE_BID_TIP })).toHaveCount(1);
	await expect(page.getByRole('button', { name: UNASSIGN_TIP })).toHaveCount(2);

	// Assign the remaining bid; no pending bids left, three Unassigns.
	await page.getByRole('button', { name: APPROVE_BID_TIP }).first().click();
	await expect(page.getByRole('button', { name: APPROVE_BID_TIP })).toHaveCount(0);
	await expect(page.getByRole('button', { name: UNASSIGN_TIP })).toHaveCount(3);

	// Each accepted reviewer's address is under their name, so the AE can invite them in
	// the venue's own reviewing system.
	await expect(page.getByTestId('assignee-email')).toHaveCount(3);
	await expect(
		page.getByTestId('assignee-email').getByRole('link', { name: SEED.scholars.r1.email })
	).toHaveAttribute('href', `mailto:${SEED.scholars.r1.email}`);
	await expect(page.getByTestId('assignee-orcid')).toHaveCount(3);

	// Back on the submissions list, bidding for that submission's Reviewer role
	// should now be closed (3 approved Reviewer assignments meets desired=3).
	await page.goto(`/venue/${VENUE_PATH}/submissions`);
	// Scoped to the row: a done submission's cells read "bidding closed" too.
	await expect(
		page.locator('tr', { hasText: SUBMISSION_EXTERNAL_ID }).getByText('bidding closed')
	).toBeVisible();

	await logout(page);

	// An author of a venue that names its reviewers sees who was assigned, but not their
	// addresses: those are for the approvers who must invite them.
	sql(`update public.venues set anonymous_assignments = false where id = '${VENUE_ID}';`);
	try {
		await login(SEED.scholars.author1.email, page, context);
		await page.goto(`/venue/${VENUE_PATH}/submission/${SUBMISSION_ID}`);
		await page.waitForLoadState('networkidle');
		await expect(page.getByRole('link', { name: SEED.scholars.r1.name })).toBeVisible();
		await expect(page.getByTestId('assignee-email')).toHaveCount(0);
		await expect(page.getByTestId('assignee-orcid')).toHaveCount(0);
		await logout(page);
	} finally {
		sql(`update public.venues set anonymous_assignments = true where id = '${VENUE_ID}';`);
	}
});

test('approvers are reminded that assigning is only for compensation, linked to the reviewing system when given', async ({
	page,
	context
}) => {
	// Query string with & on purpose: the address is escaped on its way into markdown, and
	// the link must still reach it intact.
	const REVIEW_SYSTEM = 'https://mc.manuscriptcentral.com/tok?a=1&b=2';
	const setSystem = (url: string | null) =>
		sql(
			`update public.venues set review_system_url = ${url === null ? 'null' : `'${url}'`} where id = '${VENUE_ID}';`
		);
	setSystem(null);

	try {
		// The Associate Editor, above the bids they answer: the reminder, unlinked.
		await login('ae@uni.edu', page, context);
		await page.goto(`/venue/${VENUE_PATH}/submission/${SUBMISSION_ID}`);
		await page.waitForLoadState('networkidle');
		const reminder = page.getByTestId('compensation-only');
		await expect(reminder).toBeVisible();
		await expect(reminder).toContainText('Assigning here is only for compensation.');
		await expect(reminder.getByRole('link')).toHaveCount(0);

		// Once the venue gives its reviewing system's address, the reminder links to it.
		setSystem(REVIEW_SYSTEM);
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(reminder.getByRole('link')).toHaveAttribute('href', REVIEW_SYSTEM);

		// And in brief under every row whose buttons include Assign, and only those. TOK-2025-002
		// has pending work for this Associate Editor to assign (TOK-2025-001's bids are approved
		// by the first test in this file).
		await page.goto(`/venue/${VENUE_PATH}/submission/${SUBMISSION_002}`);
		await page.waitForLoadState('networkidle');
		// Every kind of Assign, by its tip: a bid, an unapproved direct assignment, a declined
		// bid, or the confirming one over a bidder's cap.
		const assignButtons = page.getByRole('button', {
			name: /^(Accept this bid for compensation|Assign for compensation|Assign this scholar)/
		});
		await expect(assignButtons.first()).toBeVisible();
		const assignCount = await assignButtons.count();
		expect(assignCount).toBeGreaterThan(0);
		await expect(page.getByTestId('assign-note')).toHaveCount(assignCount);
		await expect(page.getByTestId('assign-note').first()).toHaveText(
			'Assign in the reviewing system first, and only after the scholar has agreed.'
		);
		// The count beside those buttons is what the scholar holds, not what assigning pays.
		await expect(page.getByRole('cell', { name: /token balance$/ }).first()).toBeVisible();
		await logout(page);

		// The batch-assign form on the submissions list carries it too.
		await login('editor@uni.edu', page, context);
		await page.goto(`/venue/${VENUE_PATH}/submissions`);
		await page.waitForLoadState('networkidle');
		await expect(page.getByTestId('compensation-only')).toBeVisible();
		await logout(page);

		// A bidder, who assigns nobody, is not shown it.
		await login(SEED.scholars.r4.email, page, context);
		await page.goto(`/venue/${VENUE_PATH}/submission/${SUBMISSION_ID}`);
		await page.waitForLoadState('networkidle');
		await expect(page.getByText(SEED.submissions.tok001.title).first()).toBeVisible();
		await expect(page.getByTestId('compensation-only')).toHaveCount(0);
		await logout(page);
	} finally {
		setSystem(null);
	}
});

test('over-cap bidder shows load indicator and requires confirm to assign', async ({
	page,
	context
}) => {
	// Put that bidder at 1 active assignment with cap=1 on Reviewer so that
	// their existing bid on the submission renders as over-cap. Resets any
	// state the previous test in this file may have left behind so the test
	// is self-contained.
	sql(
		`update public.volunteers set papers = 1 where scholarid = '${BIDDER_ID}' and roleid = '${REVIEWER_ROLE}';`
	);
	sql(
		`update public.assignments set bid = true, approved = false where scholar = '${BIDDER_ID}' and submission = '${SUBMISSION_ID}';`
	);
	sql(
		`delete from public.assignments where scholar = '${BIDDER_ID}' and submission = '${SUBMISSION_002}';`
	);
	sql(
		`insert into public.assignments (venue, submission, scholar, role, bid, approved, completed) values ('${VENUE_ID}', '${SUBMISSION_002}', '${BIDDER_ID}', '${REVIEWER_ROLE}', false, true, false);`
	);

	try {
		await login('ae@uni.edu', page, context);
		await page.goto(`/venue/${VENUE_PATH}/submission/${SUBMISSION_ID}`);
		await page.waitForLoadState('networkidle');

		// That reviewer's bid row exists; the load indicator on it reads "1 / 1" and
		// is over-cap (CSS class flags it red/bold).
		const bidRow = page.locator(`tr:has-text("${SEED.filters.uniqueReviewer}")`);
		const load = bidRow.locator('[data-testid="papers-load"]');
		await expect(load).toHaveText('1 / 1, at cap');
		await expect(load).toHaveClass(/over-cap/);

		// The approve button on the over-cap bid is now Button's warn-style
		// confirm — its accessible name comes from the approveAnyway tip, not
		// the regular approveBid tip.
		const approveAnyway = bidRow.getByRole('button', { name: APPROVE_ANYWAY_TIP });
		await expect(approveAnyway).toBeVisible();

		// First click enters confirm mode; the assignment should NOT yet be approved.
		await approveAnyway.click();
		expect(
			sql(
				`select approved::text from public.assignments where scholar = '${BIDDER_ID}' and submission = '${SUBMISSION_ID}';`
			)
		).toBe('false');

		// Second click commits — assignment flips to approved.
		await bidRow.getByRole('button', { name: 'Assign over cap?' }).click();
		await expect
			.poll(() =>
				sql(
					`select approved::text from public.assignments where scholar = '${BIDDER_ID}' and submission = '${SUBMISSION_ID}';`
				)
			)
			.toBe('true');

		// Dismiss the success toasts that approval queues (one per email recipient)
		// so they don't intercept the logout click.
		const dismissButtons = page.locator('[data-testid="feedback-success"] button');
		while ((await dismissButtons.count()) > 0) {
			await dismissButtons.first().click();
		}
		await logout(page);
	} finally {
		// Restore that bidder to a seed-equivalent state so downstream tests in the
		// full suite don't see leftover approvals or an unexpected papers cap.
		sql(
			`update public.volunteers set papers = null where scholarid = '${BIDDER_ID}' and roleid = '${REVIEWER_ROLE}';`
		);
		sql(
			`update public.assignments set bid = true, approved = false where scholar = '${BIDDER_ID}' and submission = '${SUBMISSION_ID}';`
		);
		sql(
			`delete from public.assignments where scholar = '${BIDDER_ID}' and submission = '${SUBMISSION_002}';`
		);
	}
});

test('AE declines a bid with a venue reason the bidder sees, then assigns them anyway', async ({
	page,
	context
}) => {
	// The seed venue has the default reasons; the second is this one.
	const REASON = 'We selected a different scholar.';
	const DECLINE_TIP = 'Decline this bid and explain why to the bidder';
	const CONFIRM_TIP = 'Decline this bid and email your explanation to the bidder';
	const ASSIGN_ANYWAY_TIP = 'Assign this scholar after all, withdrawing the decline';
	const bidState = () =>
		sql(
			`select approved::text || '|' || coalesce(decline_reason, '') || '|' || (decline_reason_id is not null)::text from public.assignments where scholar = '${BIDDER_ID}' and submission = '${SUBMISSION_ID}';`
		);

	// Start from the seed's pending bid, whatever the tests above left behind. Runs as the
	// owner, so enforce_assignment_updates does not apply.
	const reset = () =>
		sql(
			`update public.assignments set bid = true, approved = false, declined_at = null, declined_by = null, decline_reason = null, decline_reason_id = null where scholar = '${BIDDER_ID}' and submission = '${SUBMISSION_ID}';`
		);
	reset();
	sql(`delete from public.emails where event = 'BidDeclined' and scholar = '${BIDDER_ID}';`);

	try {
		await login('ae@uni.edu', page, context);
		await page.goto(`/venue/${VENUE_PATH}/submission/${SUBMISSION_ID}`);
		await page.waitForLoadState('networkidle');

		// Decline opens a form; nothing is sent until a reason is chosen and confirmed.
		const bidRow = page.locator(`tr:has-text("${SEED.filters.uniqueReviewer}")`);
		await bidRow.getByRole('button', { name: DECLINE_TIP }).click();
		const confirm = page.getByRole('button', { name: CONFIRM_TIP });
		await expect(confirm).toBeDisabled();

		// Writing one's own requires the words; a venue reason is sent as it is.
		await page.getByTestId('decline-reason-own').check();
		await expect(confirm).toBeDisabled();
		await page.getByTestId('decline-reasons').getByText(REASON).click();
		await expect(page.getByTestId('decline-bid-reason')).toHaveCount(0);
		await expect(confirm).toBeEnabled();
		await confirm.click();

		await expect.poll(bidState).toBe(`false|${REASON}|true`);
		await expect
			.poll(() =>
				sql(
					`select args->>4 from public.emails where event = 'BidDeclined' and scholar = '${BIDDER_ID}' order by time_sent desc limit 1;`
				)
			)
			.toBe(REASON);

		// The approver now sees it as declined, with the reason, and no longer as pending.
		await expect(page.getByTestId('declined-bid')).toContainText('Declined');
		await expect(page.getByTestId('declined-bid-reason')).toContainText(REASON);
		await expect(
			page
				.locator(`tr:has-text("${SEED.filters.uniqueReviewer}")`)
				.getByRole('button', { name: APPROVE_BID_TIP })
		).toHaveCount(0);

		const dismissButtons = page.locator('[data-testid="feedback-success"] button');
		while ((await dismissButtons.count()) > 0) await dismissButtons.first().click();
		await logout(page);

		// The bidder sees the answer and the reason in place of their bid, with no way to
		// withdraw it and bid again.
		await login(SEED.scholars.r4.email, page, context);
		await page.goto(`/venue/${VENUE_PATH}/submissions`);
		await page.waitForLoadState('networkidle');
		const declinedCell = page.locator('[data-testid^="bid-declined-"]').filter({ hasText: REASON });
		await expect(declinedCell).toBeVisible();
		await expect(declinedCell).toContainText('bid declined');
		await logout(page);

		// The approver changes their mind; assigning clears the decline.
		await login('ae@uni.edu', page, context);
		await page.goto(`/venue/${VENUE_PATH}/submission/${SUBMISSION_ID}`);
		await page.waitForLoadState('networkidle');
		await page.getByTestId('declined-bid').getByRole('button', { name: ASSIGN_ANYWAY_TIP }).click();
		await expect.poll(bidState).toBe('true||false');

		while ((await dismissButtons.count()) > 0) await dismissButtons.first().click();
		await logout(page);
	} finally {
		reset();
	}
});

test('assigning someone directly first asks whether they agreed', async ({ page, context }) => {
	const SUBMISSION_003 = SEED.submissions.tok003.id;
	const assignee = SEED.scholars.r5;
	const forget = () =>
		sql(
			`delete from public.assignments where submission = '${SUBMISSION_003}' and scholar = '${assignee.id}' and role = '${REVIEWER_ROLE}';`
		);
	const count = () =>
		sql(
			`select count(*) from public.assignments where submission = '${SUBMISSION_003}' and scholar = '${assignee.id}' and role = '${REVIEWER_ROLE}';`
		).trim();
	forget();

	try {
		await login('editor@uni.edu', page, context);
		await page.goto(`/venue/${VENUE_PATH}/submission/${SUBMISSION_003}`);
		await page.waitForLoadState('networkidle');

		await page.getByTestId('new-assignment-role').selectOption({ label: SEED.roles.reviewerName });
		await page.getByTestId('new-assignment-scholar').fill(assignee.email);
		await page.getByTestId('new-assignment-scholar').blur();
		const assign = page.getByTestId('new-assignment');
		await expect(assign).toBeEnabled();

		// The first click only asks; cancelling it assigns nobody.
		await assign.click();
		await expect(assign).toHaveText('Scholar agreed, assign');
		await page.getByRole('button', { name: '✖' }).click();
		await expect(assign).toHaveText('+ assignee');
		expect(count()).toBe('0');

		// Asking and confirming assigns them.
		await assign.click();
		await assign.click();
		await expect.poll(count).toBe('1');
	} finally {
		forget();
		await logout(page);
	}
});

test('an associate editor sees a reviewer’s true load before inviting them past their cap', async ({
	page,
	context
}) => {
	// r1 is past their cap and reviews submissions handled by more than one associate editor,
	// so the assignments ae@uni.edu may SELECT are fewer than r1 really has. The count the
	// page shows must be the real one.
	const r1 = SEED.scholars.r1;
	const active = sql(
		`select count(*) from public.assignments where scholar = '${r1.id}' and role = '${REVIEWER_ROLE}' and approved and not completed;`
	).trim();
	const visibleToAE = sql(
		`select count(*) from public.assignments a where a.scholar = '${r1.id}' and a.role = '${REVIEWER_ROLE}' and a.approved and not a.completed and exists (select 1 from public.assignments e where e.submission = a.submission and e.scholar = '${SEED.scholars.ae.id}' and e.approved);`
	).trim();
	const cap = sql(
		`select papers from public.volunteers where scholarid = '${r1.id}' and roleid = '${REVIEWER_ROLE}';`
	).trim();
	expect(Number(visibleToAE)).toBeLessThan(Number(active));
	expect(Number(cap)).toBeLessThan(Number(active));
	const shown = `${active} / ${cap}, over cap`;

	await login(SEED.scholars.ae.email, page, context);
	try {
		// Before assigning: the "+ assignee" form shows the load, warns, and asks both
		// questions in one confirmation.
		await page.goto(`/venue/${VENUE_PATH}/submission/${SUBMISSION_002}`);
		await page.waitForLoadState('networkidle');
		await page.getByTestId('new-assignment-role').selectOption({ label: SEED.roles.reviewerName });
		await page.getByTestId('new-assignment-scholar').fill(r1.email);
		await page.getByTestId('new-assignment-scholar').blur();
		await expect(page.getByTestId('new-assignment-load')).toHaveText(shown);
		await expect(page.getByTestId('new-assignment-over-cap')).toBeVisible();
		const assign = page.getByTestId('new-assignment');
		await assign.click();
		await expect(assign).toHaveText('Over cap, scholar agreed, assign');
		await page.getByRole('button', { name: '✖' }).click();

		// The roster, where editors scout for reviewers, shows the same count.
		await page.goto(`/venue/${VENUE_PATH}/volunteers`);
		await page.waitForLoadState('networkidle');
		await expect(
			page
				.locator(`tr:has-text("${r1.email}")`)
				.getByTestId('papers-load')
				.filter({ hasText: `/ ${cap}` })
		).toHaveText(shown);
		await logout(page);

		// And r1 sees the count editors see, with the reminder to correct for invitations
		// RR never heard about.
		await login(r1.email, page, context);
		await page.goto(`/venue/${VENUE_PATH}`);
		await page.waitForLoadState('networkidle');
		await expect(page.getByTestId('volunteer-load')).toContainText(`You have ${active} active`);
	} finally {
		await logout(page);
	}
});
