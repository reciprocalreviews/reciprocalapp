import adapter from '@sveltejs/adapter-vercel';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vitest/config';

export default defineConfig({
	plugins: [
		sveltekit({
			// Consult https://kit.svelte.dev/docs/integrations#preprocessors
			// for more information about preprocessors
			preprocess: vitePreprocess(),

			// Co-located with the Supabase project, which is in AWS us-west-1. The function
			// defaulted to iad1, so every server-side query was a cross-country round trip
			// (~130ms); sfo1 makes it ~10ms. The cost is ~60ms of TTFB for eastern and
			// European visitors. The landing page used to cancel that out by being
			// prerendered; it is now rendered per request and cached on the CDN for anonymous
			// visitors instead (see PUBLICLY_CACHEABLE in src/hooks.server.ts), so only the
			// first visitor in a region pays the round trip and the rest are served locally —
			// while a signed-in scholar gets a header that is right in the first byte, which
			// prerendering could not give them. `regions` belongs here rather than in
			// vercel.json: the adapter writes it into the function's .vc-config.json, which is
			// what the Build Output API actually reads.
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
		}),

		{
			name: 'watch-static',
			handleHotUpdate: ({ file, server }) => {
				if (file.includes('static')) {
					server.ws.send({
						type: 'full-reload'
					});
				}
			}
		}
	],
	test: {
		include: ['src/**/*.unit.ts'],
		// Transforming modules is most of a unit run; this persists the result under
		// node_modules so a rerun reuses it. Local only — CI's `npm ci` wipes
		// node_modules, so every CI run starts cold regardless. If a transform ever
		// looks stale (the cache key cannot see plugin options), `vitest --clearCache`.
		fsModuleCache: true
	}
});
