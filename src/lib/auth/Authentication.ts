import type { ScholarID } from '$lib/types/Scholar';

/** An interface that defaults authentication functionality. */
export default abstract class Authentication {
	abstract getScholarID(): ScholarID;

	abstract logout(): void;
}
