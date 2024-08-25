import { getContext } from 'svelte';
import type Database from './data/Database';

export const DatabaseSymbol = Symbol('database');
export const AuthSymbol = Symbol('auth');

/**  */
export function getDB() {
	return getContext<Database>(DatabaseSymbol);
}
