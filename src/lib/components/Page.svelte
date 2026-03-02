<script lang="ts">
	import type { Snippet } from 'svelte';
	import Lead from './Lead.svelte';
	import Link from './Link.svelte';
	import { type Result } from '$lib/data/CRUD';
	import EditableText from './EditableText.svelte';
	import { ScholarLabel, SubmissionLabel, VenueLabel } from './Labels';

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
</script>

<svelte:head>
	<title>{title}</title>
</svelte:head>

<section class="page">
	<div class="metadata">
		{#if breadcrumbs.length > 0}
			<div class="breadcrumbs">
				{#each breadcrumbs as url, index}
					<Link
						to={url[0]}
						icon={url[0].startsWith('/venue')
							? VenueLabel
							: url[0].startsWith('/scholar')
								? ScholarLabel
								: url[0].startsWith('/submission')
									? SubmissionLabel
									: null}>{url[1]}</Link
					>{#if index < breadcrumbs.length - 1}&gt;{/if}
				{/each}
			</div>
		{/if}
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
	{@render children()}
</section>

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: calc(1.5 * var(--spacing));
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

	.breadcrumbs {
		font-size: var(--small-font-size);
		display: flex;
		flex-direction: row;
		gap: var(--spacing-half);
	}
</style>
