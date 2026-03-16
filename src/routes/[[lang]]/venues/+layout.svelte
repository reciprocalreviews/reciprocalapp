<script lang="ts">
	import { reloadOnChanges } from '$lib/data/SupabaseRealtime';

	let { children } = $props();

	// Reload any venue or proposal changes.
	reloadOnChanges('venues_changes', [
		{ table: 'proposals', filter: undefined },
		{ table: 'venues', filter: undefined }
	]);
</script>

{@render children()}
