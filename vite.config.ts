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
		include: ['src/**/*.unit.ts']
	}
});
