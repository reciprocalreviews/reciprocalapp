<script lang="ts">
	import type { Snippet } from 'svelte';
	import Lead from './Lead.svelte';
	import Link from './Link.svelte';

	let {
		title,
		subtitle,
		details,
		breadcrumbs,
		children
	}: {
		title: string;
		subtitle?: Snippet;
		details?: Snippet;
		children: Snippet;
		breadcrumbs: [string, string][];
	} = $props();
</script>

<svelte:head>
	<title>{title}</title>
</svelte:head>

<section class="page">
	<div>
		{#if breadcrumbs.length > 0}
			<div class="breadcrumbs">
				{#each breadcrumbs as url, index}
					<Link to={url[0]}>{url[1]}</Link>{#if index < breadcrumbs.length - 1}&gt;{/if}
				{/each}
			</div>
		{/if}
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

	.breadcrumbs {
		font-size: var(--small-font-size);
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
	}
</style>
