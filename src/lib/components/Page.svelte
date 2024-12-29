<script lang="ts">
	import type { Snippet } from 'svelte';
	import Lead from './Lead.svelte';

	let { title, subtitle, children }: { title: string; subtitle?: Snippet; children: Snippet } =
		$props();
</script>

<svelte:head>
	<title>{title}</title>
</svelte:head>

<section class="page">
	<div>
		<h1>{title}</h1>
		{#if subtitle}
			<Lead>{@render subtitle()}</Lead>
		{/if}
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
</style>
