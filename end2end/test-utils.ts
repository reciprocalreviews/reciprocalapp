import { execSync } from 'node:child_process';
import { expect, type BrowserContext, type Page } from '@playwright/test';
import { login } from '../src/routes/login';

/**
 * Run a SQL statement against the local Supabase Postgres and return the trimmed
 * stdout. `-t -A` give tuples-only, unaligned output; `-q` suppresses the
 * trailing command tag (e.g. "INSERT 0 1") so callers using RETURNING get back
 * only the value.
 *
 * This was previously copy-pasted into nine separate test files; keeping a single
 * implementation here means one place to harden (e.g. escaping, container name).
 */
export function sql(statement: string): string {
	return execSync(
		`docker exec supabase_db_reciprocalapp psql -U postgres -d postgres -t -A -q -c ${JSON.stringify(statement)}`,
		{ encoding: 'utf-8' }
	).trim();
}

/**
 * Stable identifiers seeded by `supabase/seed.sql`. Referencing these by name
 * (e.g. `SEED.scholars.editor.email`) instead of redeclaring raw UUIDs in every
 * file keeps the suite readable and makes seed changes a single-file edit.
 */
export const SEED = {
	/** "Transactions on Knowledge" */
	venue: 'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
	/** Epistemology */
	currency: 'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
	roles: {
		reviewer: 'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81'
	},
	submissions: {
		/** TOK-2025-001 — full-workflow submission (reviewing, with bids) */
		tok001: 'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c12'
	},
	scholars: {
		editor: {
			email: 'editor@uni.edu',
			id: 'd181d165-8b6a-4d79-ad28-a9aece21d813',
			orcid: '0000-0001-2345-6793',
			name: 'Scholar Lee'
		},
		ae: {
			email: 'ae@uni.edu',
			id: 'b8a805bf-0aae-4443-9185-de019a8715db',
			orcid: '0000-0001-2345-6794',
			name: 'Grant Seeker'
		},
		author1: {
			email: 'author1@uni.edu',
			id: 'b8a805bf-0aae-4443-9185-de019a8715cb',
			orcid: '0000-0001-2345-6792',
			name: 'Foot Note'
		},
		author2: {
			email: 'author2@uni.edu',
			id: 'b8a805bf-0aae-4443-9185-de019a8715ec',
			orcid: '0000-0001-2345-6795',
			name: 'Ann Thesis'
		},
		r1: {
			email: 'r1@uni.edu',
			id: '7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
			orcid: '0000-0001-2345-6789',
			name: 'Rigor Russ'
		},
		r2: {
			email: 'r2@uni.edu',
			id: '7ff8621a-cbe0-4789-bbee-f008d38c4ac8',
			orcid: '0000-0001-2345-6790',
			name: 'Reese Urcher'
		},
		r3: {
			email: 'r3@uni.edu',
			id: '7ff8621a-cbe0-4789-bbee-f008d38c4ac9',
			orcid: '0000-0001-2345-6791',
			name: 'Sai Entist'
		},
		r4: {
			email: 'r4@uni.edu',
			id: '7ff8621a-cbe0-4789-bbee-f008d38c4aca',
			orcid: '0000-0001-2345-6796',
			name: 'Manny Script'
		},
		r5: {
			email: 'r5@uni.edu',
			id: '7ff8621a-cbe0-4789-bbee-f008d38c4acb',
			orcid: '0000-0001-2345-6797',
			name: 'Anne Notation'
		}
	}
} as const;

/**
 * Wait until the page is interactive by waiting for a known element to be
 * visible, rather than `waitForLoadState('networkidle')`. Networkidle blocks on
 * *all* network going quiet (up to 30s, and flaky if anything keeps polling);
 * waiting for the specific content a test needs is both faster and a more honest
 * readiness signal. Pass a testid (string) or any Locator.
 */
export async function waitForReady(page: Page, target: string) {
	await expect(page.getByTestId(target)).toBeVisible();
}

/**
 * Log in and navigate to `path`. Folds the `login → goto` preamble repeated at
 * the top of nearly every test. Optionally wait for a known testid to confirm
 * the destination has hydrated before the test interacts with it.
 */
export async function loginAndGoto(
	page: Page,
	context: BrowserContext,
	email: string,
	path: string,
	readyTestId?: string
) {
	await login(email, page, context);
	await page.goto(path);
	if (readyTestId) await waitForReady(page, readyTestId);
}
