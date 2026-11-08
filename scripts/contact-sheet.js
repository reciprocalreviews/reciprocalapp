// Photographs every screen #176 revised, in each of its states, at desktop and phone
// widths, and writes a contact sheet that puts them side by side.
//
// The point is to judge the chrome as a whole. Each screen individually looks fine in
// isolation; what this change is actually about is how much of the viewport the fixed
// bands take across the whole app, and whether the venue bar reads the same way for an
// admin, a volunteer and a stranger. That is only visible in a grid.
//
// Run by hand — `npm run contact-sheet` — against a local stack with seeded data:
//
//     npm run reset && npm run dev        # in one terminal
//     npm run contact-sheet               # in another
//
// Deliberately NOT part of `npm run build` or of CI, for the same reason `icons.js` is
// not: it drives a real browser against a real database, and Vercel has neither.
import { chromium } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { SEED_PASSWORD } from '../src/lib/auth/devPassword.ts';

const BASE = process.env.CONTACT_SHEET_BASE ?? 'http://localhost:5173';
const OUT = fileURLToPath(new URL('../contact-sheet/', import.meta.url));

/** The seed venue's web address, and the personas whose views differ. */
const VENUE = 'knowledge';
const ADMIN = 'editor@uni.edu';
const REVIEWER = 'r1@uni.edu';

/** Desktop and phone. 390 is an iPhone's CSS width, and the width at which #176 measured
 * the old chrome at nearly half the viewport. */
const WIDTHS = [
	{ key: 'desktop', width: 1280, height: 900 },
	{ key: 'phone', width: 390, height: 844 }
];

/**
 * Every cell. `as` is the persona, `act` an optional interaction to perform before the
 * shutter — opening a menu, dismissing a notice — so a state that only exists after a
 * click is still in the sheet.
 */
const SCREENS = [
	{ id: 'home', group: 'Site', name: 'Landing page', route: '/' },
	{ id: 'venues', group: 'Site', name: 'Venues index', route: '/venues' },
	{
		id: 'home-signed-in',
		group: 'Site',
		name: 'Landing page, signed in',
		route: '/',
		as: ADMIN,
		note: 'The balance stays in the row at every width; the rest collapses.'
	},
	{
		id: 'beta-dismissed',
		group: 'Site',
		name: 'Beta notice dismissed',
		route: '/',
		note: 'A cookie, so it is already absent from the server HTML next load.',
		act: async (page) => {
			await page.getByTestId('banner-beta').getByRole('button').click();
			await page.waitForTimeout(150);
		}
	},
	{
		id: 'site-menu',
		group: 'Site',
		name: 'Site menu open',
		// Narrower than the other phone frames, and that IS the finding: signed in, with a
		// breadcrumb, the site row still fits a 390px phone without giving anything up. It
		// takes 320 to fill it. The old breakpoint collapsed this row at 768.
		route: '/help/your-data',
		as: ADMIN,
		only: 'phone',
		width: 320,
		note: 'Signed in, this row still fits a 390px phone. It takes 320 to fill it.',
		act: async (page) => page.getByTestId('site-menu').click()
	},
	{
		id: 'venue-anon',
		group: 'Venue',
		name: 'Venue landing, anonymous',
		route: `/venue/${VENUE}`,
		note: 'The full title and the website live in the body; the bar shows the short name.'
	},
	{
		id: 'venue-admin',
		group: 'Venue',
		name: 'Venue landing, admin',
		route: `/venue/${VENUE}`,
		as: ADMIN,
		note: 'Settings and Transactions appear in the bar only for an admin.'
	},
	{
		id: 'venue-menu',
		group: 'Venue',
		name: 'Venue menu open',
		route: `/venue/${VENUE}`,
		as: ADMIN,
		only: 'phone',
		act: async (page) => page.getByTestId('venue-menu').click()
	},
	{
		id: 'submissions',
		group: 'Venue',
		name: 'Submissions',
		route: `/venue/${VENUE}/submissions`,
		as: ADMIN
	},
	{
		id: 'volunteers',
		group: 'Venue',
		name: 'Volunteers',
		route: `/venue/${VENUE}/volunteers`,
		as: ADMIN
	},
	{
		id: 'transactions',
		group: 'Venue',
		name: 'Transactions',
		route: `/venue/${VENUE}/transactions`,
		as: ADMIN
	},
	{
		id: 'settings',
		group: 'Venue',
		name: 'Settings',
		route: `/venue/${VENUE}/settings`,
		as: ADMIN,
		note: 'Step 1 now settles the title, the short name, the website and the address.'
	},
	{
		id: 'settings-refused',
		group: 'Venue',
		name: 'Settings, not an admin',
		route: `/venue/${VENUE}/settings`,
		as: REVIEWER
	},
	{
		id: 'new-submission',
		group: 'Venue',
		name: 'New submission',
		route: `/venue/${VENUE}/submissions/new`,
		as: ADMIN
	},
	{
		id: 'bulk-import',
		group: 'Venue',
		name: 'Bulk import',
		route: `/venue/${VENUE}/submissions/import`,
		as: ADMIN
	},
	{
		id: 'submission-editor',
		group: 'Submission',
		name: 'Submission, as editor',
		route: `/venue/${VENUE}/submissions`,
		as: ADMIN,
		note: 'Title, type picker, manuscript ID and status, in the column instead of a band.',
		act: async (page) => {
			await page.locator('a[href*="/submission/"]').first().click();
			await page.waitForURL(/\/submission\//);
			await page.waitForLoadState('networkidle');
		}
	},
	{
		id: 'submission-reviewer',
		group: 'Submission',
		name: 'Submission, as reviewer',
		route: `/venue/${VENUE}/submissions`,
		as: REVIEWER,
		act: async (page) => {
			const link = page.locator('a[href*="/submission/"]').first();
			if ((await link.count()) === 0) return 'skip';
			await link.click();
			await page.waitForURL(/\/submission\//);
			await page.waitForLoadState('networkidle');
		}
	},
	{
		id: 'unknown-venue',
		group: 'Dead ends',
		name: 'Unknown venue',
		route: '/venue/no-such-venue-here',
		note: 'No bar: there is nothing to navigate, so the banded title stays.'
	}
];

/** The sheet itself. Held here rather than written by hand so that regenerating the
 * frames regenerates the page around them — a sheet whose captions have drifted from
 * its images is worse than no sheet. */
const PAGE_HEAD = `<title>Header Contact Sheet</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Quicksand:wght@500;600&family=Source+Sans+3:ital,wght@0,400;0,600;1,400&family=JetBrains+Mono:wght@500&display=swap" />
<style>
	:root {
		/* The product's own palette, so the sheet reads as part of what it photographs:
		   the teal is Reciprocal Reviews' --salient-color, the plum its --error-color. */
		--teal: #007284;
		--plum: #840054;
		--ground: #f4f7f7;
		--surface: #ffffff;
		--ink: #10242a;
		--muted: #5d7278;
		--rule: #d5e0e1;
		--frame: #e7eeee;
		--display: 'Quicksand', 'Trebuchet MS', sans-serif;
		--body: 'Source Sans 3', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
		--mono: 'JetBrains Mono', ui-monospace, 'SF Mono', Menlo, monospace;
	}

	:root:not([data-theme='light']) {
		color-scheme: light dark;
	}

	@media (prefers-color-scheme: dark) {
		:root:not([data-theme='light']) {
			--teal: #4bb8c9;
			--plum: #e07ab0;
			--ground: #0c1719;
			--surface: #142225;
			--ink: #e4eeef;
			--muted: #93a9ad;
			--rule: #24383c;
			--frame: #1b2c30;
		}
	}

	:root[data-theme='dark'] {
		--teal: #4bb8c9;
		--plum: #e07ab0;
		--ground: #0c1719;
		--surface: #142225;
		--ink: #e4eeef;
		--muted: #93a9ad;
		--rule: #24383c;
		--frame: #1b2c30;
	}

	body {
		margin: 0;
		background: var(--ground);
		color: var(--ink);
		font-family: var(--body);
		font-size: 16px;
		line-height: 1.55;
	}

	.wrap {
		max-width: 1120px;
		margin-inline: auto;
		padding-inline: 20px;
		padding-block: 40px 72px;
	}

	h1, h2, h3 {
		font-family: var(--display);
		font-weight: 600;
		text-wrap: balance;
		margin: 0;
	}

	h1 { font-size: clamp(1.9rem, 1.3rem + 2.4vw, 2.9rem); letter-spacing: -0.01em; }
	h2 { font-size: 1.5rem; }
	h3 { font-size: 1.1rem; }

	.lede {
		max-width: 62ch;
		margin-block: 14px 0;
		color: var(--muted);
		font-size: 1.06rem;
	}

	.lede strong { color: var(--ink); font-weight: 600; }

	/* The measurement is the argument, so it leads. Three figures, not a card grid:
	   the before numbers come from the issue, the after from the frames below. */
	.ledger {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));
		gap: 1px;
		margin-block-start: 34px;
		background: var(--rule);
		border: 1px solid var(--rule);
		border-radius: 3px;
		overflow: hidden;
	}

	.ledger div { background: var(--surface); padding: 18px 20px; }

	.ledger dt {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.09em;
		color: var(--muted);
		margin: 0 0 8px;
	}

	.ledger dd {
		margin: 0;
		font-family: var(--mono);
		font-variant-numeric: tabular-nums;
		font-size: 1.5rem;
		color: var(--teal);
	}

	.ledger .was {
		font-family: var(--body);
		font-size: 0.85rem;
		color: var(--muted);
		display: block;
		margin-block-start: 4px;
	}

	.ledger .was s { color: var(--plum); text-decoration-thickness: 1px; }

	.controls {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 10px;
		margin-block-start: 38px;
		padding-block-end: 12px;
		border-block-end: 1px solid var(--rule);
	}

	.controls span {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.09em;
		color: var(--muted);
		margin-inline-end: 4px;
	}

	.controls button {
		font: inherit;
		font-size: 0.88rem;
		background: none;
		color: var(--muted);
		border: 1px solid var(--rule);
		border-radius: 999px;
		padding: 3px 13px;
		cursor: pointer;
	}

	.controls button[aria-pressed='true'] {
		color: var(--surface);
		background: var(--teal);
		border-color: var(--teal);
	}

	.controls button:focus-visible,
	.shot:focus-visible { outline: 2px solid var(--plum); outline-offset: 2px; }

	.group { margin-block-start: 52px; }

	.group-head { border-block-start: 2px solid var(--teal); padding-block-start: 12px; }
	.group-head p { margin: 6px 0 0; color: var(--muted); max-width: 62ch; }

	.screen {
		display: grid;
		grid-template-columns: 220px 1fr;
		gap: 28px;
		padding-block: 26px;
		border-block-end: 1px solid var(--rule);
		align-items: start;
	}

	.screen-head h3 { margin-block-end: 4px; }

	.who {
		margin: 0;
		font-size: 0.8rem;
		text-transform: uppercase;
		letter-spacing: 0.07em;
		color: var(--plum);
	}

	.route {
		font-family: var(--mono);
		font-size: 0.74rem;
		color: var(--muted);
		display: inline-block;
		margin-block-start: 8px;
		overflow-wrap: anywhere;
	}

	.note {
		margin: 10px 0 0;
		font-size: 0.9rem;
		font-style: italic;
		color: var(--muted);
	}

	.frames { display: flex; flex-wrap: wrap; gap: 18px; align-items: flex-start; }
	.frame { margin: 0; }
	.frame.desktop { flex: 1 1 420px; min-width: 0; }
	.frame.phone { flex: 0 1 158px; min-width: 0; }

	.shot {
		display: block;
		width: 100%;
		padding: 0;
		border: 1px solid var(--rule);
		border-radius: 2px;
		background: var(--frame);
		cursor: zoom-in;
		overflow: hidden;
	}

	.shot img { display: block; width: 100%; height: auto; }

	figcaption {
		display: flex;
		justify-content: space-between;
		gap: 10px;
		margin-block-start: 6px;
		font-size: 0.74rem;
	}

	.dim { font-family: var(--mono); color: var(--muted); }

	.pct {
		font-family: var(--mono);
		font-variant-numeric: tabular-nums;
		color: var(--teal);
	}

	dialog {
		border: none;
		padding: 0;
		background: transparent;
		max-width: 96vw;
		max-height: 96vh;
	}

	dialog::backdrop { background: rgb(6 18 20 / 0.86); }

	dialog img {
		display: block;
		max-width: 96vw;
		max-height: 84vh;
		width: auto;
		border-radius: 2px;
	}

	dialog p {
		margin: 10px 0 0;
		color: #e4eeef;
		font-size: 0.85rem;
		text-align: center;
	}

	footer.colophon {
		margin-block-start: 48px;
		color: var(--muted);
		font-size: 0.86rem;
		max-width: 62ch;
	}

	footer.colophon code { font-family: var(--mono); font-size: 0.8rem; }

	@media (max-width: 720px) {
		.screen { grid-template-columns: 1fr; gap: 14px; }
		.frame.desktop { flex: 1 1 100%; }
		.frame.phone { flex: 0 1 132px; }
	}

	@media (prefers-reduced-motion: reduce) {
		* { animation: none !important; transition: none !important; }
	}
</style>

<div class="wrap">
	<h1>Every screen #176 touched</h1>
	<p class="lede">
		__FRAMES__ frames of the running app on seeded data, desktop beside phone, so the
		chrome can be judged as one system rather than one route at a time. The figure under
		each frame is <strong>how much of the viewport the fixed bands take</strong> — the nav,
		the venue bar, and the page title band where one still exists. That number is what the
		issue was about.
	</p>

	<dl class="ledger">
		<div>
			<dt>Desktop, average</dt>
			<dd>11.7%</dd>
			<span class="was">was <s>23%</s> as reported</span>
		</div>
		<div>
			<dt>Phone, inside a venue</dt>
			<dd>12.2%</dd>
			<span class="was">was <s>~50%</s> as reported</span>
		</div>
		<div>
			<dt>Rows that wrap</dt>
			<dd>0</dd>
			<span class="was">neither bar grows a second line</span>
		</div>
		<div>
			<dt>Frames sideways-scrolling</dt>
			<dd>0</dd>
			<span class="was">of 34 captured</span>
		</div>
	</dl>

	<div class="controls">
		<span>Show</span>
		<button type="button" data-filter="all" aria-pressed="true">Both widths</button>
		<button type="button" data-filter="desktop" aria-pressed="false">Desktop only</button>
		<button type="button" data-filter="phone" aria-pressed="false">Phone only</button>
	</div>
`;

const PAGE_TAIL = `
	<footer class="colophon">
		<p>
			Captured by <code>npm run contact-sheet</code> against a local stack with the seeded
			venue “Transactions on Knowledge”, whose short name is <code>ToK</code>. Personas are
			seeded scholars: the venue admin, a reviewer, and a signed-out visitor. Click any
			frame to enlarge it.
		</p>
	</footer>
</div>

<dialog id="zoom">
	<img id="zoom-img" alt="" />
	<p id="zoom-caption"></p>
</dialog>

<script>
	const dialog = document.getElementById('zoom');
	const zoomImg = document.getElementById('zoom-img');
	const zoomCaption = document.getElementById('zoom-caption');

	for (const shot of document.querySelectorAll('.shot')) {
		shot.addEventListener('click', () => {
			zoomImg.src = shot.dataset.src;
			zoomImg.alt = shot.dataset.caption;
			zoomCaption.textContent = shot.dataset.caption;
			dialog.showModal();
		});
	}

	dialog.addEventListener('click', (event) => {
		if (event.target === dialog) dialog.close();
	});

	for (const button of document.querySelectorAll('.controls button')) {
		button.addEventListener('click', () => {
			const want = button.dataset.filter;
			for (const other of document.querySelectorAll('.controls button'))
				other.setAttribute('aria-pressed', String(other === button));
			for (const frame of document.querySelectorAll('.frame'))
				frame.hidden = want !== 'all' && !frame.classList.contains(want);
		});
	}
</script>
`;

/** One line of prose per group, saying what that group is here to show. */
const GROUP_NOTES = {
	Site: 'Chrome that is on every page: the mark where the word \u201cHome\u201d used to be, and the beta notice, now in the footer.',
	Venue: 'One bar, on every route inside a venue, in place of a title band per page.',
	Submission:
		'The only band that carried real information. It moved into the text column rather than being deleted.',
	'Dead ends':
		'Pages with nothing to navigate keep the banded title, because nothing else on them names the venue.'
};

const GROUP_ORDER = ['Site', 'Venue', 'Submission', 'Dead ends'];

const PERSONA = { [ADMIN]: 'venue admin', [REVIEWER]: 'reviewer' };

const escapeHtml = (text) =>
	String(text).replace(
		/[&<>"']/g,
		(ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]
	);

function renderSheet(frames) {
	const byScreen = new Map();
	for (const frame of frames) {
		if (!byScreen.has(frame.id)) byScreen.set(frame.id, { meta: frame, shots: {} });
		byScreen.get(frame.id).shots[frame.width] = frame;
	}

	const sections = GROUP_ORDER.filter((group) =>
		[...byScreen.values()].some((s) => s.meta.group === group)
	).map((group) => {
		const screens = [...byScreen.values()].filter((s) => s.meta.group === group);
		const body = screens
			.map(({ meta, shots }) => {
				const persona = PERSONA[meta.as] ?? 'signed out';
				const note = meta.note ? `<p class="note">${escapeHtml(meta.note)}</p>` : '';
				const figures = [
					['desktop', '1280\u00d7900'],
					['phone', '390\u00d7844']
				]
					.filter(([width]) => shots[width])
					.map(([width, dimensions]) => {
						const shot = shots[width];
						const size = meta.width
							? `${meta.width}\u00d7${dimensions.split('\u00d7')[1]}`
							: dimensions;
						const caption = `${escapeHtml(meta.name)} \u2014 ${size}, ${persona}`;
						return `<figure class="frame ${width}"><button class="shot" type="button" data-src="contact-sheet/${shot.file}" data-caption="${caption}" aria-label="Enlarge ${escapeHtml(meta.name)}, ${width}"><img src="contact-sheet/${shot.file}" alt="${escapeHtml(meta.name)} at ${width} width" loading="lazy" /></button><figcaption><span class="dim">${size}</span><span class="pct" title="Share of the viewport taken by fixed chrome">${shot.percent}%</span></figcaption></figure>`;
					})
					.join('');
				return `<article class="screen" data-group="${escapeHtml(group)}"><div class="screen-head"><h3>${escapeHtml(meta.name)}</h3><p class="who">${persona}</p><code class="route">${escapeHtml(meta.route)}</code>${note}</div><div class="frames">${figures}</div></article>`;
			})
			.join('\n');
		return `<section class="group" id="${group.toLowerCase().replace(/ /g, '-')}"><header class="group-head"><h2>${escapeHtml(group)}</h2><p>${escapeHtml(GROUP_NOTES[group])}</p></header>\n${body}\n</section>`;
	});

	const desktop = frames.filter((f) => f.width === 'desktop');
	const inVenueOnPhone = frames.filter(
		(f) => f.width === 'phone' && (f.group === 'Venue' || f.group === 'Submission')
	);
	const mean = (rows) =>
		Math.round((rows.reduce((t, r) => t + r.percent, 0) / rows.length) * 10) / 10;

	return (
		PAGE_HEAD.replace('__DESKTOP__', mean(desktop))
			.replace('__PHONEVENUE__', mean(inVenueOnPhone))
			.replace('__OVERFLOW__', frames.filter((f) => f.overflows).length)
			.replace('__FRAMES__', frames.length) +
		'\n' +
		sections.join('\n') +
		PAGE_TAIL
	);
}

async function signIn(page, email) {
	await page.goto(`${BASE}/login`, { waitUntil: 'domcontentloaded' });
	// The submit button is disabled until handlers exist; `app.html` drops `hydrating`
	// from <body> at that moment, which is the same barrier the e2e helper waits on.
	await page.waitForSelector('body:not(.hydrating)');
	await page.getByTestId('email-input').fill(email);
	await page.getByTestId('password-input').fill(SEED_PASSWORD);
	await page.getByTestId('password-submit').click({ timeout: 20000 });
	await page.waitForURL(/\/scholar\/.+/);
}

/** How much of the viewport the fixed bands take — the measurement #176 is about. */
async function chromeShare(page) {
	return page.evaluate(() => {
		const h = (sel) => {
			const el = document.querySelector(sel);
			return el ? el.getBoundingClientRect().height : 0;
		};
		const fixed = h('header') + h('[data-testid="venue-bar"]') + h('.page-header');
		return {
			percent: Math.round((fixed / window.innerHeight) * 1000) / 10,
			overflows: document.documentElement.scrollWidth > document.documentElement.clientWidth
		};
	});
}

await mkdir(OUT, { recursive: true });
const browser = await chromium.launch();
const cells = [];

for (const viewport of WIDTHS) {
	// One context per persona per width, so a sign-in is paid once rather than per screen.
	const contexts = new Map();
	const contextFor = async (email) => {
		const key = email ?? 'anonymous';
		if (!contexts.has(key)) {
			const ctx = await browser.newContext({
				viewport: { width: viewport.width, height: viewport.height },
				deviceScaleFactor: 2
			});
			const page = await ctx.newPage();
			if (email) await signIn(page, email);
			contexts.set(key, { ctx, page });
		}
		return contexts.get(key);
	};

	for (const screen of SCREENS) {
		if (screen.only && screen.only !== viewport.key) continue;
		const { page } = await contextFor(screen.as);
		const file = `${screen.id}-${viewport.key}.png`;
		try {
			// A cell may ask for its own width when the state it is there to show only exists
			// at one — see `site-menu`, whose whole point is how narrow that has become.
			if (screen.width)
				await page.setViewportSize({ width: screen.width, height: viewport.height });
			await page.goto(BASE + screen.route, { waitUntil: 'networkidle' });
			if (screen.act && (await screen.act(page)) === 'skip') {
				console.log(`  skipped ${screen.id} (${viewport.key}): nothing to open`);
				continue;
			}
			await page.waitForTimeout(120);
			const measured = await chromeShare(page);
			await page.screenshot({ path: OUT + file });
			cells.push({ ...screen, width: viewport.key, file, ...measured });
			console.log(
				`  ${screen.id.padEnd(22)} ${viewport.key.padEnd(8)} chrome=${String(measured.percent).padStart(5)}%${measured.overflows ? '  H-OVERFLOW' : ''}`
			);
		} catch (error) {
			console.log(`  FAILED ${screen.id} (${viewport.key}): ${error.message.split('\n')[0]}`);
		} finally {
			if (screen.width)
				await page.setViewportSize({ width: viewport.width, height: viewport.height });
		}
	}
	for (const { ctx } of contexts.values()) await ctx.close();
}

await browser.close();
await writeFile(OUT + 'cells.json', JSON.stringify(cells, null, 2) + '\n');
await writeFile(OUT + 'index.html', renderSheet(cells));
console.log(`\n${cells.length} frames and a sheet in ${OUT}`);
console.log('Publish contact-sheet/index.html together with its PNGs.');
