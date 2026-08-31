import adapter from '@sveltejs/adapter-vercel';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	// Consult https://kit.svelte.dev/docs/integrations#preprocessors
	// for more information about preprocessors
	preprocess: vitePreprocess(),

	kit: {
		// Co-located with the Supabase project, which is in AWS us-west-1. The function
		// defaulted to iad1, so every server-side query was a cross-country round trip
		// (~130ms); sfo1 makes it ~10ms. The cost is ~60ms of TTFB for eastern and
		// European visitors, which the prerendered landing page cancels out for the page
		// most of them arrive on. `regions` belongs here rather than in vercel.json: the
		// adapter writes it into the function's .vc-config.json, which is what the Build
		// Output API actually reads.
		adapter: adapter({ regions: ['sfo1'] }),
		// The default version.name is a build timestamp, so it changes on every
		// deployment. pollInterval makes the client check for a newer version in the
		// background; `updated.current` ($app/state) flips true when one is found,
		// which drives the update-available banner.
		version: { pollInterval: 300000 },
		alias: {
			$data: 'src/data',
			$routes: 'src/routes',
			// The locale JSON is imported into the bundle rather than fetched at
			// runtime. It stays in `static/` because `npm run locale-validate`
			// globs `static/locales/*.json`, and because it is still served there
			// for anything that wants to read a locale over HTTP.
			$locales: 'static/locales'
		}
	}
};

export default config;
