<script lang="ts">
	import type { Snippet } from 'svelte';

	let { children }: { children: Snippet } = $props();
</script>

<div class="cards">
	{@render children()}
</div>

<style>
	.cards {
		display: flex;
		flex-wrap: wrap;
		flex-direction: row;
		justify-content: space-around;
		gap: calc(3 * var(--spacing));
	}
</style>
