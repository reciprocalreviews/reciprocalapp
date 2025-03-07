<script lang="ts">
	import type { Snippet } from 'svelte';
	import Lead from './Lead.svelte';
	import Link from './Link.svelte';
	import { type Result } from '$lib/data/CRUD';
	import EditableText from './EditableText.svelte';

	let {
		title,
		subtitle,
		details,
		breadcrumbs,
		children,
		edit
	}: {
		title: string;
		subtitle?: Snippet;
		details?: Snippet;
		children: Snippet;
		breadcrumbs: [string, string][];
		edit?:
			| {
					valid: undefined | ((text: string) => string | undefined);
					update: (text: string) => Promise<Result>;
					placeholder: string;
			  }
			| undefined;
	} = $props();

	let revisedTitle = $state(title);
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
		<h1>
			{#if edit}<EditableText
					text={revisedTitle}
					valid={edit.valid}
					edit={edit.update}
					placeholder={edit.placeholder}
				></EditableText>{:else}{title}{/if}
		</h1>
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
