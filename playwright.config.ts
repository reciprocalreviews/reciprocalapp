import { type PlaywrightTestConfig, devices } from '@playwright/test';
import process from 'node:process';

const config: PlaywrightTestConfig = {
	// Locally, reset the DB to the seed state before the suite so accumulated
	// mutations from previous runs don't break tests (CI gets a fresh DB per run
	// and skips this — see end2end/global-setup.ts).
	globalSetup: './end2end/global-setup.ts',
	webServer: {
		// Sync types, build with vite, start Supabase locally without the services
		// the suite doesn't use, then run the preview server.
		//
		// One command for both CI and local, deliberately. This used to branch —
		// local ran `emu`, which chained `npm start`, which ends in
		// `supabase functions serve`: a blocking foreground process, so
		// `npm run preview` never ran and Playwright sat here until the timeout
		// below expired. CI was unaffected because its variant excluded the edge
		// runtime, which meant the local suite was broken for ten minutes at a time
		// while CI stayed green. `start:test` therefore excludes edge-runtime
		// everywhere, and nothing in end2end/ needs it: every email assertion reads
		// the `emails` table directly with the `sql()` helper (the verification
		// token is pulled out of `emails.args`), never a delivered message, and
		// `send_email()`'s pg_net POST is best-effort and swallows its own failure.
		//
		// If you want mail logged to the console while developing, run `npm start`
		// in another terminal — that path still serves functions.
		command: 'npm run emu',
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
	// final summary. In CI we shard across runners (see playwright.yml), so each
	// shard emits a `blob` report; a downstream merge-reports job stitches the
	// shards into one HTML report. `github` adds inline PR annotations on failure.
	// Locally we keep the self-contained HTML report.
	reporter: process.env.CI
		? [['list'], ['github'], ['blob']]
		: [['list'], ['html', { open: 'never' }]],
	// One worker per process. Parallelism comes from sharding across runners in
	// CI (each shard = its own Supabase). `fullyParallel` is intentionally left
	// off so sharding splits by whole file, preserving intra-file ordering.
	workers: 1,
	// Two retries in CI absorb intermittent flakes on slow/contended runners
	// (submission-creation tests do long DB round-trip chains). Locally we
	// keep retries=0 so flakes are caught and investigated.
	retries: process.env.CI ? 2 : 0,
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
