// Release: fast-forward `main` to `dev` and push, which is what triggers
// production.yml.
//
// This was a one-line npm script (`git checkout main && git merge dev && ...`)
// until #148-#150 landed directly on `main` and sat there for a week. `git
// merge dev` did not care: it would have reconciled two diverged branches for
// the first time in the commit that deploys them, so the tree reaching
// production would have been one no CI run, and no staging deploy, had ever
// seen. That is the single most dangerous moment in this repository, and it
// arrived disguised as a routine release.
//
// So the merge is now `--ff-only`, and the checks below explain the refusal
// rather than leaving `git` to say "not possible to fast-forward". The fix in
// every case is the same: merge `main` into `dev`, verify on staging, release
// from there.

import { spawnSync } from 'child_process';

/** Run a command, inheriting stdio; exit with its status if it fails. */
function run(command, args) {
	const result = spawnSync(command, args, { stdio: 'inherit' });
	if (result.status !== 0) process.exit(result.status ?? 1);
}

/** Run a command quietly and return its trimmed stdout. */
function capture(command, args) {
	const result = spawnSync(command, args, { encoding: 'utf-8' });
	return (result.stdout ?? '').trim();
}

function refuse(reason, fix) {
	console.error(`\nRefusing to deploy: ${reason}\n\n${fix}\n`);
	process.exit(1);
}

run('git', ['fetch', 'origin', '--quiet']);

// Uncommitted work would ride along into the release, or block the checkout.
if (capture('git', ['status', '--porcelain']) !== '') {
	refuse('the working tree has uncommitted changes.', 'Commit or stash them first.');
}

// The invariant: everything on `main` is already on `dev`. When it holds, the
// merge is a fast-forward and production gets exactly the tree staging ran.
const contained = spawnSync('git', ['merge-base', '--is-ancestor', 'origin/main', 'dev']);
if (contained.status !== 0) {
	refuse(
		'`main` has commits `dev` does not, so the branches have diverged.',
		'Run `git checkout dev && git merge main`, resolve, let staging verify it, then deploy.'
	);
}

// `dev` must also be pushed, or staging validated something other than this.
if (capture('git', ['rev-parse', 'dev']) !== capture('git', ['rev-parse', 'origin/dev'])) {
	refuse(
		'`dev` differs from `origin/dev`.',
		'Push `dev` and let the staging deploy finish before releasing it.'
	);
}

run('git', ['checkout', 'main']);
run('git', ['merge', '--ff-only', 'dev']);
run('git', ['push']);
run('git', ['checkout', 'dev']);
