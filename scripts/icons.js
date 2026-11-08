// Rasterizes static/brand/logo.svg into the PNGs that SVG cannot cover: iOS ignores SVG
// touch icons, and Open Graph consumers (Slack, LinkedIn, iMessage) reject SVG
// outright. Everything else uses static/brand/favicon.svg directly.
//
// Run by hand — `npm run icons` — and commit the output. Deliberately NOT part of
// `npm run build`: that runs on Vercel, which has no Chromium for Playwright to
// drive, so wiring it in would break every deploy.
import { chromium } from '@playwright/test';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const logo = await readFile(`${root}static/brand/logo.svg`, 'utf8');

// Fonts are inlined as data URIs rather than linked with file:// URLs. `setContent`
// leaves the page on an `about:blank` origin, and Chromium refuses file:// subresource
// loads from one — the card silently rasterizes in a fallback face instead.
async function font(path) {
	return `url(data:font/woff2;base64,${(await readFile(`${root}${path}`)).toString('base64')}) format('woff2')`;
}
const quicksand = await font('static/fonts/Quicksand/Quicksand500-3.woff2');
const josefin = await font('static/fonts/Josefin/JosefinSansVariable.woff2');

// The mark is inlined into the page rather than referenced with <img src>, because
// an <img> would not let CSS reach inside to recolor it white for the social card.
const page = (body, css) => `<!doctype html><meta charset="utf-8" />
	<style>
		@font-face { font-family: 'Quicksand'; font-weight: 500; src: ${quicksand}; }
		@font-face { font-family: 'Josefin Sans'; font-weight: 100 700; src: ${josefin}; }
		html, body { margin: 0; background: transparent; }
		${css}
	</style>${body}`;

const targets = [
	{
		file: 'favicon.png',
		width: 96,
		height: 96,
		transparent: true,
		// The shadow is sub-pixel noise at this size; favicon.svg drops it for the
		// same reason, so strip the ghost group here rather than shrink it.
		html: page(
			`<div class="icon">${logo.replace(/<g opacity[\s\S]*?<\/g>/, '')}</div>`,
			`.icon { width: 96px; height: 96px; display: grid; place-items: center; }
			 svg { width: 96px; height: 96px; }`
		)
	},
	{
		file: 'apple-touch-icon.png',
		width: 180,
		height: 180,
		// iOS composites this onto an opaque rounded tile, so unlike every other
		// artifact here it deliberately carries a background.
		html: page(
			`<div class="tile">${logo}</div>`,
			`.tile { width: 180px; height: 180px; background: #fff; display: grid; place-items: center; }
			 svg { width: 128px; height: 128px; }`
		)
	},
	{
		file: 'og-image.png',
		width: 1200,
		height: 630,
		html: page(
			`<div class="card">${logo}<h1>Reciprocal Reviews</h1><p>Make peer review count.</p></div>`,
			`.card { width: 1200px; height: 630px; background: #007284; color: #fff;
			         display: flex; flex-direction: column; align-items: center;
			         justify-content: center; gap: 28px; }
			 .card svg { width: 190px; height: 190px; }
			 .card svg g { fill: #fff; }
			 h1 { font-family: 'Quicksand', sans-serif; font-weight: 500; font-size: 76px; margin: 0; }
			 p { font-family: 'Josefin Sans', sans-serif; font-weight: 300; font-style: italic;
			     font-size: 38px; margin: 0; }`
		)
	}
];

const browser = await chromium.launch();
for (const target of targets) {
	const tab = await browser.newPage({
		viewport: { width: target.width, height: target.height },
		// Without this the screenshot comes out at twice the requested dimensions.
		deviceScaleFactor: 1
	});
	await tab.setContent(target.html, { waitUntil: 'load' });
	// Otherwise the card can rasterize in a fallback face.
	await tab.evaluate(() => document.fonts.ready);
	await writeFile(
		`${root}static/brand/${target.file}`,
		await tab.screenshot({ omitBackground: target.transparent === true })
	);
	await tab.close();
	console.log(`wrote static/brand/${target.file}`);
}
await browser.close();
