<script lang="ts">
	import { getContext, type Snippet } from 'svelte';
	import Lead from './Lead.svelte';
	import { type Result } from '$lib/data/CRUD';
	import EditableText from './EditableText.svelte';

	let {
		icon,
		title,
		subtitle,
		details,
		breadcrumbs,
		children,
		edit
	}: {
		icon: string;
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

	let revisedTitle = $derived(title);

	const breadcrumbsContext = getContext<{ breadcrumbs: [string, string][] }>('breadcrumbs');
	$effect(() => {
		if (breadcrumbsContext) breadcrumbsContext.breadcrumbs = breadcrumbs;
	});
</script>

<svelte:head>
	<title>{title}</title>
</svelte:head>

<section class="page">
	<div class="metadata">
		<h1 data-testid="page-header">
			<span class="emoji">{icon}</span>
			{#if edit}<EditableText
					text={revisedTitle}
					valid={edit.valid}
					edit={edit.update}
					placeholder={edit.placeholder}
				></EditableText>{:else}{title}{/if}
		</h1>
		<div class="details">
			{#if subtitle}<Lead>{@render subtitle()}</Lead>{/if}{@render details?.()}
		</div>
	</div>
	<div class="content">
		{@render children()}
	</div>
</section>

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: calc(2 * var(--spacing));
		margin: auto;
		width: 100%;
	}

	.emoji {
		font-family: 'Noto Emoji', 'Josefin Sans', sans-serif;
		font-size: 80%;
	}

	h1 {
		display: flex;
		gap: 0.5rem;
		align-items: center;
	}

	.page > :global(p) {
		margin-block-end: 0;
	}

	.metadata {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
	}

	.details {
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
		align-items: baseline;
		font-size: var(--small-font-size);
	}

	.details,
	.content {
		padding-left: calc(var(--spacing) * 2);
		padding-right: calc(var(--spacing) * 2);
	}

	.content {
		display: flex;
		flex-direction: column;
		gap: calc(2 * var(--spacing));
	}
</style>
