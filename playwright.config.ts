import { type PlaywrightTestConfig, devices } from '@playwright/test';
import process from 'node:process';

const config: PlaywrightTestConfig = {
	webServer: {
		// Sync types, build with vite, run the preview server, and start Supabase locally, without services we don't use.
		command: process.env.CI ? 'npm run emu:ci' : 'npm run emu',
		name: 'dev',
		reuseExistingServer: !process.env.CI,
		port: 4173,
		stderr: 'pipe',
		stdout: 'pipe',
		// 10 minutes. CI runners with a cold Docker cache need ~3-5 min just to
		// pull Supabase's images before `start` returns; locally with a warm
		// cache this finishes in seconds, so the higher ceiling is only ever
		// consumed when CI actually needs it.
		timeout: 600_000
	},
	use: {
		screenshot: 'only-on-failure'
	},
	// `list` prints each test name with its pass/fail status as it runs, so
	// CI logs show progress instead of jumping from "Running N tests" to the
	// final summary. `html` keeps producing the rich report artifact, and
	// `github` adds inline annotations on the PR/run page when tests fail.
	reporter: process.env.CI
		? [['list'], ['github'], ['html', { open: 'never' }]]
		: [['list'], ['html', { open: 'never' }]],
	workers: 1,
	// One retry in CI absorbs intermittent flakes. Locally we
	// keep retries=0 so flakes are caught and investigated.
	retries: process.env.CI ? 1 : 0,
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
