<script lang="ts">
	import type { Snippet } from 'svelte';
	import Lead from './Lead.svelte';

	let {
		title,
		subtitle,
		details,
		children
	}: { title: string; subtitle?: Snippet; details?: Snippet; children: Snippet } = $props();
</script>

<svelte:head>
	<title>{title}</title>
</svelte:head>

<section class="page">
	<div>
		<h1>{title}</h1>
		<div class="details">
			<Lead>{@render subtitle?.()}</Lead>{@render details?.()}
		</div>
	</div>
	{@render children()}
</section>

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: calc(2 * var(--spacing));
		max-width: 40em;
		margin: auto;
	}
	.details {
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
		align-items: baseline;
		font-size: var(--small-font-size);
	}
</style>
