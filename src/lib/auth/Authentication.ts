import type { ScholarID } from '../../data/types';

/** An interface that defines an authentication state interface. Useful if we want to migrate to other auth providers. */
export default abstract class Authentication<UserKind, ErrorKind> {
	abstract setUser(user: UserKind | null): void;
	abstract getUserID(): string | null;
	abstract signIn(
		email: string,
		password: string | undefined
	): Promise<ErrorKind | ScholarID | null>;
	abstract isAuthenticated(): boolean;
	abstract signOut(): Promise<ErrorKind | null>;
}
