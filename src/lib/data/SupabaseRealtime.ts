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

/** This SvelteKit helper function sets up the listener on mount, invalidates a page when relevant data changes, and cleans up the subscription on unmount. */
export function reloadOnChanges(
	name: string,
	filters: { table: string; filter: string | undefined }[]
) {
	const db = getDB();
	onMount(() => {
		const subscription = getRealtimeChannel(name, db().client, filters, () => {
			// Brute force reload all of the page data. Thanks SvelteKit.
			invalidateAll();
		}).subscribe();

		return () => {
			subscription.unsubscribe();
		};
	});
}
