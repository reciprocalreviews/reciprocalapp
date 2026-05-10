// Run `npm run updates` only in CI. Locally, the updates.json that ships
// with the build is whatever was last regenerated for a release; skipping
// the step keeps local `npm run build` (and the Playwright `emu` flow)
// from rewriting that file on every iteration.

import { spawnSync } from 'child_process';

if (!process.env.CI) {
	console.log('Skipping `npm run updates` outside of CI.');
	process.exit(0);
}

const result = spawnSync('npm', ['run', 'updates'], { stdio: 'inherit' });
process.exit(result.status ?? 0);
