/** An interface that defines an authentication state interface. Useful if we want to migrate to other auth providers. */
export default abstract class Authentication<UserKind> {
	abstract setUser(user: UserKind | null): void;
	abstract getUserID(): string | null;
	abstract isAuthenticated(): boolean;
	abstract signOut(): void;
}
