import { getContext } from 'svelte';
import type Database from './data/Database';
import { writable, type Writable } from 'svelte/store';
import type Authentication from './auth/Authentication';

export const DatabaseSymbol = Symbol('database');
export const AuthSymbol = Symbol('auth');

/**  */
export function getDB() {
	return getContext<Database>(DatabaseSymbol);
}

/** A store that's either the active authenticated user or nothing, indicating that no one is logged in. */
export const Auth = writable<Authentication | null>(null);

export function getAuth(): Writable<Authentication | null> {
	return getContext<Writable<Authentication | null>>(AuthSymbol);
}
