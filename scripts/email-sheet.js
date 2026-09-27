// Renders example emails with the real template registry and branded shell, photographs
// each at an email client's width and a phone's, and photographs the profile control that
// silences them -- so wording and layout can be judged before any of it is sent.
//
// Run by hand -- `npm run email-sheet` -- ideally against a local stack with seeded data, for
// the profile frames:
//
//     npm run reset && npm run dev        # in one terminal
//     npm run email-sheet                 # in another
//
// Without a dev server the emails are still rendered; only the profile frames are skipped.
// Like contact-sheet.js, deliberately NOT part of the build or of CI.
import { chromium } from '@playwright/test';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { SEED_PASSWORD } from '../src/lib/auth/devPassword.ts';
import { renderEmail, settingsUrlFor } from '../supabase/functions/_shared/templates.ts';
import { renderBrandedEmail } from '../supabase/functions/_shared/emailShell.ts';
import {
	HostileDigest,
	ReeseDigest,
	TwoVenueDigest,
	totalOf
} from '../src/email/biddingDigest.fixtures.ts';

const BASE = process.env.CONTACT_SHEET_BASE ?? 'http://localhost:5173';
const ORIGIN = 'https://reciprocal.reviews';
const OUT = fileURLToPath(new URL('../contact-sheet/emails/', import.meta.url));

/** Reese Urcher in supabase/seed.sql, whose digest ReeseDigest is. */
const REESE = { email: 'r2@uni.edu', id: '7ff8621a-cbe0-4789-bbee-f008d38c4ac8' };
const EDITOR_ID = '00000000-0000-4000-8000-000000000000';
const SUBMISSION = 'f0000002-ad50-11f0-9000-000000000010';

const WIDTHS = [
	{ key: 'client', width: 640 },
	{ key: 'phone', width: 390 }
];

function digest(payload) {
	const total = totalOf(payload);
	return [JSON.stringify(payload), `${total} submission${total === 1 ? '' : 's'}`];
}

/** Every email frame: the template, its arguments, and who it is addressed to. */
const EMAILS = [
	{
		id: 'digest',
		name: 'Weekly digest, one venue',
		note: 'Reese Urcher’s real open submissions from the seed. Need first; the two “peer review” matches lead their tiers.',
		event: 'BiddingDigest',
		args: digest(ReeseDigest),
		scholar: REESE.id
	},
	{
		id: 'digest-two-venues',
		name: 'Weekly digest, two venues',
		note: 'Groups sort by venue name. A group lists seven and counts the rest.',
		event: 'BiddingDigest',
		args: digest(TwoVenueDigest),
		scholar: REESE.id
	},
	{
		id: 'digest-hostile',
		name: 'Weekly digest, hostile titles',
		note: 'Markup, a link and entities in scholar-supplied fields all render as inert text.',
		event: 'BiddingDigest',
		args: digest(HostileDigest),
		scholar: REESE.id
	},
	{
		id: 'new-bid',
		name: 'An existing optional notice',
		note: 'Every silenceable email now ends with where to turn it off.',
		event: 'NewBid',
		args: ['Retraction Notices as a Genre', 'Reviewer', 'knowledge', SUBMISSION],
		scholar: EDITOR_ID
	},
	{
		id: 'call-for-bids',
		name: 'An optional notice with its own Reply-To',
		note: 'The settings sentence follows the reply-to footer too.',
		event: 'CallForBids',
		args: [
			'Transactions on Knowledge',
			'Ed Itor',
			'editor',
			'We have three papers without a single referee. If any of them is close to your work, please bid this week.',
			'Reviewer',
			'knowledge'
		],
		scholar: REESE.id,
		replyTo: 'editor@uni.edu'
	},
	{
		id: 'assignment-approved',
		name: 'A consequential notice',
		note: 'Cannot be silenced, so it offers no settings link.',
		event: 'AssignmentApproved',
		args: ['Ed Itor', 'editor@uni.edu', 'Reviewer', 'knowledge', SUBMISSION],
		scholar: REESE.id
	}
];

const escapeHtml = (text) =>
	String(text).replace(
		/[&<>"']/g,
		(ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]
	);

await mkdir(OUT, { recursive: true });
const browser = await chromium.launch();
const cells = [];

for (const email of EMAILS) {
	const { subject, message } = renderEmail(email.event, email.args, ORIGIN);
	const { html, text } = renderBrandedEmail(
		subject,
		message,
		ORIGIN,
		email.replyTo,
		false,
		settingsUrlFor(email.event, email.scholar, ORIGIN)
	);
	await writeFile(`${OUT}${email.id}.html`, html);
	await writeFile(`${OUT}${email.id}.txt`, `Subject: ${subject}\n\n${text}\n`);
	const shots = {};
	for (const { key, width } of WIDTHS) {
		const page = await browser.newPage({ viewport: { width, height: 800 }, deviceScaleFactor: 2 });
		await page.setContent(html, { waitUntil: 'load' });
		const file = `${email.id}-${key}.png`;
		await page.screenshot({ path: OUT + file, fullPage: true });
		await page.close();
		shots[key] = file;
	}
	cells.push({ kind: 'email', ...email, subject, text, shots });
	console.log(`  ${email.id.padEnd(22)} ${subject}`);
}

// The sign-in email is hand-written HTML sent by Supabase Auth rather than rendered from the
// registry, so it is shown from its template with the placeholders filled in.
{
	const html = (
		await readFile(new URL('../supabase/templates/magic_link.html', import.meta.url), 'utf8')
	)
		.replaceAll('{{ .ConfirmationURL }}', `${ORIGIN}/auth/v1/verify?token=example`)
		.replaceAll('{{ .Token }}', '314159');
	const shots = {};
	for (const { key, width } of WIDTHS) {
		const page = await browser.newPage({ viewport: { width, height: 800 }, deviceScaleFactor: 2 });
		await page.setContent(html, { waitUntil: 'load' });
		const file = `magic-link-${key}.png`;
		await page.screenshot({ path: OUT + file, fullPage: true });
		await page.close();
		shots[key] = file;
	}
	cells.push({
		kind: 'email',
		id: 'magic-link',
		name: 'Sign-in email (Supabase Auth)',
		note: 'Hand-written template, given the same button.',
		shots
	});
	console.log('  magic-link             sign-in email');
}

/** The Reviewing group of the profile's notification controls: its heading through its
 * fieldset, which is where the new checkbox lands. */
async function shootSettings(width, key) {
	const page = await browser.newPage({ viewport: { width, height: 900 }, deviceScaleFactor: 2 });
	try {
		await page.goto(`${BASE}/login`, { waitUntil: 'domcontentloaded' });
		await page.waitForSelector('body:not(.hydrating)');
		await page.getByTestId('email-input').fill(REESE.email);
		await page.getByTestId('password-input').fill(SEED_PASSWORD);
		await page.getByTestId('password-submit').click({ timeout: 20000 });
		await page.waitForURL(/\/scholar\/.+/);
		await page.goto(`${BASE}/scholar/${REESE.id}`, { waitUntil: 'networkidle' });
		const heading = page.locator('#notifications-reviewing');
		await heading.waitFor();
		await heading.scrollIntoViewIfNeeded();
		const box = await page.evaluate(() => {
			const head = document.getElementById('notifications-reviewing');
			let set = head.nextElementSibling;
			while (set && set.tagName !== 'FIELDSET') set = set.nextElementSibling;
			const a = head.getBoundingClientRect();
			const b = set.getBoundingClientRect();
			const pad = 16;
			return {
				x: Math.max(0, Math.min(a.left, b.left) - pad * 3),
				y: Math.max(0, a.top - pad),
				width:
					Math.min(window.innerWidth, Math.max(a.right, b.right) + pad) -
					Math.max(0, Math.min(a.left, b.left) - pad),
				height: b.bottom - a.top + pad * 2
			};
		});
		const file = `settings-${key}.png`;
		await page.screenshot({ path: OUT + file, clip: box });
		return file;
	} finally {
		await page.close();
	}
}

try {
	const shots = {};
	for (const { key, width } of [
		{ key: 'desktop', width: 1280 },
		{ key: 'phone', width: 390 }
	])
		shots[key] = await shootSettings(width, key);
	cells.push({
		kind: 'settings',
		id: 'settings',
		name: 'Profile › Notifications › Reviewing',
		note: 'Generated from the registry, so the new control needs no page change. On by default.',
		shots
	});
	console.log('  settings               profile control');
} catch (error) {
	console.log(`  skipped settings: ${error.message.split('\n')[0]} (is ${BASE} up?)`);
}

await browser.close();
await writeFile(OUT + 'cells.json', JSON.stringify(cells, null, 2) + '\n');
await writeFile(
	OUT + 'index.html',
	`<!doctype html><meta charset="utf-8"><title>Email sheet</title><body style="font-family:sans-serif">` +
		cells
			.map(
				(c) =>
					`<h2>${escapeHtml(c.name)}</h2><p>${escapeHtml(c.note)}</p>` +
					Object.values(c.shots)
						.map((f) => `<img src="${f}" style="max-width:48%;vertical-align:top">`)
						.join(' ')
			)
			.join('\n')
);
console.log(`\n${cells.length} cells in ${OUT}`);
