import { type BrowserContext, type Page } from '@playwright/test';

/** A reusable function for logging in using the email OTP method */
export async function login(email: string, page: Page, context: BrowserContext) {
	// Visit the login page
	await page.goto('/login');

	// Fill in the email input and submit the form
	await page.getByTestId('email-input').fill(email);
	await page.getByTestId('email-submit').click();

	// Visit the mailpit server
	const mailpit = await context.newPage();
	await mailpit.goto('http://localhost:54324');

	// Click the first message in the list
	await mailpit.locator('.message').first().click();

	// Get the third paragraph with the OTP code
	const text = await mailpit.frameLocator('#preview-html').locator('p').nth(2).textContent();

	// Extract the code using a regular expression
	const codeMatch = text?.match(/(\d{6})/);

	// Back on the login page, enter the code into the OTP input and submit the form.
	await page.getByTestId('otp-input').fill(codeMatch ? codeMatch[1] : '');
	await page.getByTestId('otp-submit').click();
}

/** A reusable function for logging out */
export async function logout(page: Page) {
	// Click the logout button
	await page.getByTestId('logout-button').click();
}
