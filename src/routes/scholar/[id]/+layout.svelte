<script lang="ts">
	import { page } from '$app/state';
	import { reloadOnChanges } from '$lib/data/SupabaseRealtime';

	let { children } = $props();

	// Reload when the scholar data changes.
	reloadOnChanges('scholar_changes', [{ table: 'scholars', filter: `id=eq.${page.params.id}` }]);
</script>

{@render children()}
