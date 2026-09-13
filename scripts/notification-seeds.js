/**
 * Print the SQL that seeds the notification preference tables from the email registry.
 *
 * The generator itself lives in src/email/notificationSeeds.ts, next to the registry it reads
 * and inside the typechecked project; this file only transpiles it so it can be run from the
 * command line. Usage: node scripts/notification-seeds.js
 */
import { build } from 'esbuild';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const dir = mkdtempSync(join(tmpdir(), 'rr-seeds-'));
try {
	const outfile = join(dir, 'seeds.mjs');
	await build({
		entryPoints: ['src/email/notificationSeeds.ts'],
		bundle: true,
		format: 'esm',
		platform: 'neutral',
		outfile,
		logLevel: 'silent'
	});
	const { seedSQL } = await import(pathToFileURL(outfile).href);
	console.log(seedSQL());
} finally {
	rmSync(dir, { recursive: true, force: true });
}
