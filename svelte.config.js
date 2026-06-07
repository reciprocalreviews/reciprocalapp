import adapter from '@sveltejs/adapter-vercel';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	// Consult https://kit.svelte.dev/docs/integrations#preprocessors
	// for more information about preprocessors
	preprocess: vitePreprocess(),

	kit: {
		adapter: adapter(),
		// The default version.name is a build timestamp, so it changes on every
		// deployment. pollInterval makes the client check for a newer version in the
		// background; `updated.current` ($app/state) flips true when one is found,
		// which drives the update-available banner.
		version: { pollInterval: 300000 },
		alias: {
			$data: 'src/data',
			$routes: 'src/routes'
		}
	}
};

export default config;
