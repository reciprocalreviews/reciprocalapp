import type { ScholarID } from '../../data/types';

/** An interface that defines an authentication state interface. Useful if we want to migrate to other auth providers. */
export default abstract class Authentication<UserKind, ErrorKind> {
	abstract setUser(user: UserKind | null): void;
	abstract getUserID(): string | null;
	/** Begin the ORCID OIDC sign-in redirect. Resolves (with an error, or null) before
	 * the browser navigates away; on success the flow returns to `redirectTo`. */
	abstract signInWithORCID(redirectTo: string): Promise<ErrorKind | null>;
	/** LOCAL/STAGING dev-only email+password grant. Never reachable in production — the
	 * login UI only renders the form off-prod (see login/+page.svelte). Used by the
	 * Playwright suite so tests don't need a real ORCID round-trip. */
	abstract signInWithPassword(
		email: string,
		password: string
	): Promise<ErrorKind | ScholarID | null>;
	abstract isAuthenticated(): boolean;
	abstract signOut(): Promise<ErrorKind | null>;
}
