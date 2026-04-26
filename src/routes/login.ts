import { type BrowserContext, type Page } from '@playwright/test';

/** A reusable function for logging in using the email OTP method */
export async function login(email: string, page: Page, context: BrowserContext) {
	// Visit the login page
	await page.goto('/login');

	// Request the OTP email. Retry up to 3 times in case the local Supabase auth
	// service rate-limits the send (which can happen when the same email is used
	// across multiple test files in rapid succession).
	let otpSent = false;
	for (let attempt = 1; attempt <= 3; attempt++) {
		await page.getByTestId('email-input').fill(email);
		await page.getByTestId('email-submit').click();

		// Wait up to 5 seconds for the OTP input to appear (meaning the send succeeded).
		otpSent = await page
			.getByTestId('otp-input')
			.waitFor({ state: 'visible', timeout: 5000 })
			.then(() => true)
			.catch(() => false);

		if (otpSent) break;

		if (attempt < 3) {
			// Wait before retrying — 1s is the configured max_frequency but some
			// Supabase GoTrue versions enforce a longer internal window.
			await page.waitForTimeout(3000);
			await page.goto('/login');
		}
	}

	if (!otpSent) throw new Error(`login: Supabase refused to send OTP to ${email} after 3 attempts`);

	// Retrieve the OTP code from Mailpit via its REST API.  Using the API is
	// more reliable than clicking through the web UI when multiple emails for
	// the same address exist in the inbox.
	const mailpit = await context.newPage();
	let code = '';

	for (let i = 0; i < 10; i++) {
		const res = await mailpit.request.get('http://localhost:54324/api/v1/messages?limit=50');
		const json = (await res.json()) as {
			messages?: Array<{ ID: string; To: Array<{ Address: string }> }>;
		};
		// The list is newest-first; find the first message addressed to this email.
		const message = (json.messages ?? []).find((m) =>
			m.To.some((addr) => addr.Address === email)
		);
		if (message) {
			const msgRes = await mailpit.request.get(
				`http://localhost:54324/api/v1/message/${message.ID}`
			);
			const msg = (await msgRes.json()) as { Text?: string; HTML?: string };
			// Prefer plain text to avoid matching digits in URLs; look for the
			// "enter the code: XXXXXX" pattern Supabase uses in magic-link emails.
			const body = msg.Text ?? msg.HTML ?? '';
			const match = body.match(/code:\s*(\d{6})/);
			if (match) {
				code = match[1];
				break;
			}
		}
		await mailpit.waitForTimeout(1000);
	}

	await mailpit.close();

	if (!code) throw new Error(`login: could not find OTP email for ${email} in Mailpit`);

	// Enter the OTP code and submit.
	await page.getByTestId('otp-input').fill(code);
	await page.getByTestId('otp-submit').click();

	// Wait for the scholar page to be reached.
	await page.waitForURL(/\/scholar\/.+/);
}

/** A reusable function for logging out */
export async function logout(page: Page) {
	// Click the logout button
	await page.getByTestId('logout-button').click();
}
