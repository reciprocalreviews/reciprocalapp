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
 * Run a SQL statement as a particular scholar, and return its output.
 *
 * `sql()` connects as `postgres`, which has no session: `auth.uid()` is null.
 * Every RPC that moves value opens with `if auth.uid() is null then raise
 * 'Authentication required'`, so none of them can be called from a bare psql
 * connection. `auth.uid()` reads the `request.jwt.claims` GUC, so setting it
 * (transaction-locally, alongside the `authenticated` role the grants are written
 * against) is what lets a fixture call `mint_tokens`, `transfer_tokens`, or
 * `approve_transaction` the way the app does.
 *
 * Use this rather than writing `public.tokens` directly. A trigger logs every
 * write to that table into `public.token_events`, and a raw insert or delete
 * produces exactly the unattributed mint or the orphaned burn that
 * `reconcile_ledger()` exists to find — which is how the e2e suite once left four
 * pgTAP invariants failing on a clean tree (#152). `end2end/global-teardown.ts`
 * now fails the run if it happens again.
 */
export function asScholar(scholar: string, statement: string): string {
	const claims = JSON.stringify({ sub: scholar, role: 'authenticated' }).replaceAll("'", "''");
	return sql(
		`begin; set local role authenticated; set local request.jwt.claims to '${claims}'; ${statement}; commit;`
	);
}

/**
 * Stable identifiers and content seeded by `supabase/seed.sql`. Referencing these by
 * name (e.g. `SEED.scholars.editor.email`) instead of redeclaring raw UUIDs in every
 * file keeps the suite readable and makes seed changes a single-file edit.
 *
 * That applies to the seed's *user-visible text* as much as to its ids. A spec that
 * types `'Ann Thesis'` or `'Windmill'` into a filter has quietly made the seed's prose
 * part of the contract, and then nobody can improve how the local database reads
 * without a red suite to wade through first. So: no scholar name, submission title,
 * manuscript ID, venue title, currency name or mirrored ORCID string appears as a
 * literal in `end2end/` — it comes from here, and rewriting the seed's copy means
 * editing this file and nothing else.
 *
 * Ids, auth emails, ORCID iDs and amounts are a different matter: they are the seed's
 * *internal* values, tests depend on them directly, and they are meant to stay put.
 */
export const SEED = {
	venue: 'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
	/** The seed venue's web address. Venue URLs are built from this, not from the id: the
	 * id form only redirects to it, and a suite that navigates by id would be testing the
	 * redirect over and over instead of the pages. Use `venue` for SQL, this for URLs. */
	venuePath: 'knowledge',
	/** The venue's title, as it renders. */
	venueTitle: 'Transactions on Knowledge',
	currency: 'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
	/** The currency's name, as it renders. */
	currencyName: 'Epistemology',
	/** Every seeded submission's manuscript ID begins with this, and nothing else on a
	 * submissions page does — which is how a spec asserts that IDs are being withheld. */
	submissionIdPrefix: 'TOK-2025-',
	roles: {
		reviewer: 'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81'
	},
	submissions: {
		/** The full-workflow submission: reviewing, one approved reviewer and two open bids. */
		tok001: {
			id: 'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c12',
			externalId: 'TOK-2025-001',
			title: 'A Study on the Effectiveness of Peer Review Incentives in Academic Publishing'
		},
		tok002: {
			id: 'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c13',
			externalId: 'TOK-2025-002',
			title: 'A Windmill Study on the Failures of Peer Review'
		},
		tok003: {
			id: 'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c14',
			externalId: 'TOK-2025-003',
			title: 'A Reverse Engineering of Authorship from Reference Counts'
		}
	},
	/**
	 * Text fragments whose *matching behaviour* the filter specs are built on, named for
	 * the behaviour rather than the words. Renaming a seeded scholar or retitling a
	 * submission means re-checking these hold, not just pasting the new spelling in:
	 *
	 *  - `uniqueAuthor` matches exactly one scholar, who authors submissions and reviews none
	 *  - `uniqueReviewer` matches exactly one scholar, who reviews and authors nothing
	 *  - `authorAndReviewer` matches exactly one scholar, who does both
	 *  - `sharedPrefix` matches SEVERAL scholars including `scholars.author2` — the
	 *    ambiguity is the point, since it is what makes picking the right one a real choice
	 *  - `uniqueInvitee` extends `sharedPrefix` by a letter and matches only
	 *    `scholars.r5`, so a search can mix it with an iD and an email and still
	 *    resolve to exactly three people
	 *  - `uniqueTitleWord` appears in exactly one submission title and no manuscript ID
	 */
	filters: {
		uniqueAuthor: 'Foot',
		uniqueReviewer: 'Manny',
		authorAndReviewer: 'Rigor',
		sharedPrefix: 'Ann',
		uniqueInvitee: 'Anne',
		uniqueTitleWord: 'Windmill'
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
			name: 'Rigor Russ',
			/** The one seeded scholar with a full ORCID mirror, as the profile renders it. */
			orcidProfile: {
				affiliation: 'Professor, Department of Rigor, University of Test',
				education: 'Ph.D. Reproducibility',
				keyword: 'peer review',
				/** The count spans the whole record, not the few works kept. */
				works: '37 works, 2009–2025',
				work: 'On the Reproducibility of Reviewing',
				link: 'Faculty website'
			}
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
