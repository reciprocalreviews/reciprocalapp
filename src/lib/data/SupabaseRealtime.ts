import type { Database } from '$data/database';
import type { RealtimeChannel, SupabaseClient } from '@supabase/supabase-js';
import { onMount } from 'svelte';
import { getDB } from './CRUD';
import { invalidateAll } from '$app/navigation';

/** This helper function generates a realtime channel to subscribe to that calls the given callback, given a list of tables and filters */
export default function getRealtimeChannel(
	name: string,
	supabase: SupabaseClient<Database>,
	filters: { table: string; filter: string | undefined }[],
	callback: () => void
): RealtimeChannel {
	// Build a set of filters based on the filters provided.
	return filters.reduce(
		(ch, filter) =>
			ch.on(
				'postgres_changes',
				{
					// Listen to all events
					event: '*',
					schema: 'public',
					table: filter.table,
					filter: filter.filter
				},
				callback
			),
		supabase.channel(name)
	);
}

/** How long to wait for a burst of changes to finish before refetching. One
 * user-visible action routinely writes several rows — a submission inserts a
 * charge per author, an editor payout writes a transaction per editor — and each
 * arrives as its own message. Without this, each one ran every load function on
 * the page again. Short enough that a single change still feels immediate. */
const INVALIDATE_DEBOUNCE_MS = 250;

/** This SvelteKit helper function sets up the listener on mount, invalidates a page when relevant data changes, and cleans up the subscription on unmount. */
export function reloadOnChanges(
	name: string,
	filters: { table: string; filter: string | undefined }[]
) {
	const db = getDB();
	onMount(() => {
		// Coalesce a burst into one refetch. `invalidateAll` reloads *everything*
		// the page loaded, so doing it once per message multiplied one write by the
		// number of rows it happened to touch.
		let pending: ReturnType<typeof setTimeout> | undefined;
		const subscription = getRealtimeChannel(name, db().client, filters, () => {
			if (pending !== undefined) clearTimeout(pending);
			pending = setTimeout(() => {
				pending = undefined;
				// Brute force reload all of the page data. Thanks SvelteKit.
				invalidateAll();
			}, INVALIDATE_DEBOUNCE_MS);
		}).subscribe();

		return () => {
			if (pending !== undefined) clearTimeout(pending);
			subscription.unsubscribe();
		};
	});
}
