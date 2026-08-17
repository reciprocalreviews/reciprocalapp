import { test, expect } from '@playwright/test';
import { login, logout } from '../src/routes/login';

/** The seeded steward (supabase/seed.sql). */
const STEWARD_EMAIL = 'editor@uni.edu';
/** A seeded scholar who is not a steward, promoted and demoted below. */
const CANDIDATE_NAME = 'Ann Thesis';

test('the about page shows stewards', async ({ page }) => {
	await page.goto('/about');

	// Expect the about page to have a steward from seed data.
	await expect(page.getByTestId('steward-0')).toBeVisible();
});

test('a visitor sees no steward controls', async ({ page }) => {
	await page.goto('/about');

	await expect(page.getByTestId('steward-0')).toBeVisible();
	// Stewardship is managed here, but only by stewards: a signed-out visitor is
	// offered neither the add card nor any demote button.
	await expect(page.getByTestId('add-steward-card')).toHaveCount(0);
	await expect(page.getByTestId('remove-steward-0')).toHaveCount(0);
});

test('a steward can promote and demote another scholar', async ({ page, context }) => {
	await login(STEWARD_EMAIL, page, context);
	await page.goto('/about');

	const card = page.getByTestId('add-steward-card');
	await expect(card).toBeVisible();

	// One steward to begin with, so there is nobody the UI would offer to remove —
	// and the only steward is the signed-in scholar, who may not demote themselves.
	await expect(page.getByTestId('remove-steward-0')).toHaveCount(0);

	// Expand the add-steward card to reveal its form. The card is server-rendered,
	// so a click can land before Svelte has hydrated and attached the toggle, and
	// then nothing happens. Retrying until the form appears absorbs that without
	// falling back to `networkidle` — and it doubles as the hydration barrier for
	// everything below, since the field cannot exist until a handler has run.
	const field = page.getByTestId('add-steward-field');
	await expect(async () => {
		await card.click();
		await expect(field).toBeVisible({ timeout: 1000 });
	}).toPass({ timeout: 15000 });

	// Find the candidate by NAME rather than ORCID: the point of the shared scholar
	// search is that a steward need not know an identifier to appoint someone.
	await field.fill(CANDIDATE_NAME);
	const match = page.getByTestId('add-steward-field-match-0');
	await expect(match).toBeVisible();
	await match.click();

	await page.getByTestId('add-steward-button').click();

	// The list refetches, and now names both.
	await expect(page.getByTestId('steward-1')).toBeVisible();
	await expect(page.getByText(CANDIDATE_NAME).first()).toBeVisible();

	// With two stewards, the other one can be removed — and the signed-in steward
	// still cannot remove themselves, so exactly one demote button is offered.
	await expect(page.getByTestId('remove-steward-0')).toHaveCount(1);
	await expect(page.getByTestId('remove-steward-1')).toHaveCount(0);

	// Demote, confirming the two-click warning.
	await page.getByTestId('remove-steward-0').click();
	await page.getByTestId('remove-steward-0').click();

	await expect(page.getByTestId('steward-1')).toHaveCount(0);
	await expect(page.getByTestId('remove-steward-0')).toHaveCount(0);

	await logout(page);
});
