import { type PlaywrightTestConfig, devices } from '@playwright/test';

const config: PlaywrightTestConfig = {
	webServer: {
		// Sync types, build with vite, run the preview server, and start Supabase locally, without services we don't use.
		command: 'npm run emu',
		name: 'dev',
		reuseExistingServer: !process.env.CI,
		port: 4173,
		stderr: 'pipe',
		stdout: 'pipe',
		timeout: 200000
	},
	testDir: 'end2end',
	testMatch: /(.+\.)?(end)\.ts/,
	projects: [
		{
			name: 'chromium',
			use: {
				...devices['Desktop Chrome']
			}
		}
		/** Roll the dice and only test on Chromium until we have a more stable test suite.
		{
			name: 'firefox',
			use: {
				...devices['Desktop Firefox']
			}
		},
		{
			name: 'webkit',
			use: {
				...devices['Desktop Safari']
			}
		}
		*/
	]
};

export default config;
