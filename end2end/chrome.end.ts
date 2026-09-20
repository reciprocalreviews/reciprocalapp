import { expect, test } from '@playwright/test';
import { login, logout } from '../src/routes/login';
import { SEED } from './test-utils';

const VENUE = SEED.venuePath;

/**
 * The site chrome, which #176 condensed from three or four stacked bands to one row plus,
 * inside a venue, one bar. These assertions are about the chrome itself rather than about
 * any page, so they live here rather than being scattered through the route suites.
 */

test('the beta notice lives in the footer and stays dismissed', async ({ page }) => {
	await page.goto('/');
	await page.waitForLoadState('networkidle');

	const beta = page.getByTestId('banner-beta');
	await expect(beta).toBeVisible();

	// In the footer, not the sticky header: that is the whole point of moving it, since
	// the header's height is what every sticky offset below it is measured from.
	await expect(page.locator('footer').getByTestId('banner-beta')).toBeVisible();
	await expect(page.locator('header').getByTestId('banner-beta')).toHaveCount(0);

	await beta.getByRole('button').click();
	await expect(beta).toHaveCount(0);

	// The cookie, not component state, is what has to make this survive. A reload proves
	// the difference: local state would come back.
	await page.reload();
	await page.waitForLoadState('networkidle');
	await expect(page.getByTestId('banner-beta')).toHaveCount(0);
});

test('the venue bar reaches a venue from every route inside it', async ({ page }) => {
	await page.goto(`/venue/${VENUE}`);
	await page.waitForLoadState('networkidle');

	const bar = page.getByTestId('venue-bar');
	await expect(bar).toBeVisible();

	// The short name, which is what the bar exists to be able to show.
	await expect(page.getByTestId('venue-bar-home')).toContainText('ToK');

	await expect(bar.getByRole('link', { name: 'Submissions' })).toBeVisible();
	await expect(bar.getByRole('link', { name: 'Volunteers' })).toBeVisible();

	// Settings belongs to admins; an anonymous visitor would only reach a page saying so.
	await expect(bar.getByRole('link', { name: 'Settings' })).toHaveCount(0);

	// And it follows you down. The per-page title band is gone inside a venue, so the bar
	// is the only thing naming where you are.
	await bar.getByRole('link', { name: 'Volunteers' }).click();
	await page.waitForURL(new RegExp(`/venue/${VENUE}/volunteers`));
	await expect(page.getByTestId('venue-bar')).toBeVisible();

	// Link.svelte drops the href on the current route and marks it `aria-current`, which
	// is what gives the bar its active tab. Matched on the anchor rather than by role:
	// without an href it is no longer a link, which is exactly the state being asserted.
	await expect(page.getByTestId('venue-bar').locator('a[aria-current="page"]')).toContainText(
		'Volunteers'
	);
});

test('an admin gets settings in the bar', async ({ page, context }) => {
	await login(SEED.scholars.editor.email, page, context);
	await page.goto(`/venue/${VENUE}`);
	await page.waitForLoadState('networkidle');

	const bar = page.getByTestId('venue-bar');
	await expect(bar.getByRole('link', { name: 'Settings' })).toBeVisible();
	await expect(bar.getByRole('link', { name: 'Transactions' })).toBeVisible();

	await logout(page);
});

test('the chrome collapses instead of wrapping on a phone', async ({ page }) => {
	await page.setViewportSize({ width: 390, height: 800 });
	await page.goto(`/venue/${VENUE}`);
	await page.waitForLoadState('networkidle');

	// Nothing may run off the side. A sticky row in a document wider than the viewport
	// slides out of view when the reader scrolls sideways (#156).
	const overflows = await page.evaluate(
		() => document.documentElement.scrollWidth > document.documentElement.clientWidth
	);
	expect(overflows).toBe(false);

	// Both bars are one row each. Wrapping to a second is the behaviour #176 measured at
	// nearly half a phone's viewport, so this is the assertion that would catch a
	// regression to it.
	const bar = page.getByTestId('venue-bar');
	const barHeight = (await bar.boundingBox())?.height ?? 0;
	expect(barHeight).toBeLessThan(60);

	// Transactions is past the fold on a narrow screen, so it is behind the menu.
	await expect(bar.getByRole('link', { name: 'Transactions' })).toBeHidden();
	await page.getByTestId('venue-menu').click();
	await expect(bar.getByRole('link', { name: 'Transactions' })).toBeVisible();

	// Opening the menu must not grow the bar: its height is measured into
	// `--page-header-height`, which is a sticky offset for everything below it.
	expect((await bar.boundingBox())?.height ?? 0).toBeCloseTo(barHeight, 0);

	await page.keyboard.press('Escape');
	await expect(bar.getByRole('link', { name: 'Transactions' })).toBeHidden();
});
