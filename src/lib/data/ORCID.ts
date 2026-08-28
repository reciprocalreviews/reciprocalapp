export const ORCIDRegex = /^(\d{4}-){3}\d{3}(\d|X)$/;

/**
 * A scholar's public ORCID profile. An ORCID iD is itself the path of its profile URL, so
 * there is nothing to look up — but the host belongs in one place rather than inline at
 * each call site, since it is the one part that isn't derived from the iD.
 */
export function orcidURL(id: string): string {
	return `https://orcid.org/${id}`;
}

/**
 * Compute the ISO 7064 MOD 11-2 check character for a string of base digits, as ORCID
 * uses for the final character of an iD (0-9 or X). See
 * https://support.orcid.org/hc/en-us/articles/360006897674.
 */
function orcidCheckDigit(baseDigits: string): string {
	let total = 0;
	for (const digit of baseDigits) total = (total + Number(digit)) * 2;
	const remainder = total % 11;
	const result = (12 - remainder) % 11;
	return result === 10 ? 'X' : String(result);
}

/**
 * Generate a random, format- and checksum-valid ORCID iD (e.g. `0009-0004-1234-5678`).
 * Used only by the local dev-only mock ORCID sign-in to mint a fresh scholar identity
 * (see Auth.svelte.ts `signInWithMockORCID`); it does not correspond to a real person.
 */
export function generateORCID(): string {
	let base = '';
	for (let i = 0; i < 15; i++) base += Math.floor(Math.random() * 10);
	const full = base + orcidCheckDigit(base);
	return `${full.slice(0, 4)}-${full.slice(4, 8)}-${full.slice(8, 12)}-${full.slice(12, 16)}`;
}
