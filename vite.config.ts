import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vitest/config';

export default defineConfig({
	plugins: [
		sveltekit(),
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
