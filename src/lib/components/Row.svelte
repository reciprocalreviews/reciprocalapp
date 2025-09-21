<script lang="ts">
	import type { Snippet } from 'svelte';

	interface Props {
		children: Snippet;
		baseline?: boolean;
	}

	let { children, baseline = false }: Props = $props();
</script>

<div class="row" class:baseline>{@render children()}</div>

<style>
	.row {
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		gap: var(--spacing);
		row-gap: var(--spacing);
		align-items: center;
	}

	.baseline {
		align-items: baseline;
	}
</style>
