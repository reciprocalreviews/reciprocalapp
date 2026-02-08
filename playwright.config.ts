import { type PlaywrightTestConfig, devices } from '@playwright/test';

const config: PlaywrightTestConfig = {
	webServer: {
		// Sync types, build with vite, run the preview server, and start Supabase locally, without services we don't use.
		command:
			'npm run sync && npm run build && npm run preview && supabase db start --exclude storage-api,imgproxy,logflare,supavisor',
		name: 'dev',
		reuseExistingServer: !process.env.CI,
		port: 4173
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
