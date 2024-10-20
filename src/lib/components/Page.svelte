<script lang="ts">
	import type { Snippet } from 'svelte';
	import Lead from './Lead.svelte';

	let {
		title,
		subtitle,
		children
	}: { title: string; subtitle?: string | undefined; children: Snippet } = $props();
</script>

<svelte:window {title} />

<section class="page">
	<div>
		<h1>{title}</h1>
		{#if subtitle}
			<Lead class="subtitle">{subtitle}</Lead>
		{/if}
	</div>
	{@render children()}
</section>

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: calc(2 * var(--spacing));
		max-width: 35em;
		margin: auto;
	}
</style>
