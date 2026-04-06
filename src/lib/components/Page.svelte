<script lang="ts">
	import { type Result } from '$lib/data/CRUD';
	import type LocaleText from '$lib/locales/Locale';
	import { getLocaleContext } from '$routes/Contexts';
	import { getContext, type Snippet } from 'svelte';
	import EditableText from './EditableText.svelte';
	import Lead from './Lead.svelte';

	let {
		icon,
		title,
		subtitle,
		details,
		breadcrumbs,
		children,
		wobble = false,
		edit
	}: {
		icon: string;
		title: string | ((l: LocaleText) => string);
		subtitle?: Snippet;
		details?: Snippet;
		children: Snippet;
		breadcrumbs: [string, string][];
		wobble?: boolean;
		edit?:
			| {
					valid: undefined | ((text: string) => ((l: LocaleText) => string) | undefined);
					update: (text: string) => Promise<Result>;
					placeholder: (l: LocaleText) => string;
			  }
			| undefined;
	} = $props();

	const locale = getLocaleContext();

	let revisedTitle = $derived(typeof title === 'function' ? title(locale()) : title);

	const breadcrumbsContext = getContext<{ breadcrumbs: [string, string][] }>('breadcrumbs');
	$effect(() => {
		if (breadcrumbsContext) breadcrumbsContext.breadcrumbs = breadcrumbs;
	});
</script>

<svelte:head>
	<title>{revisedTitle}</title>
</svelte:head>

<section class="page">
	<div class="metadata">
		<h1 class:wobble data-testid="page-header">
			<span class="emoji">{icon}</span>
			{#if edit}<EditableText
					text={revisedTitle}
					valid={edit.valid}
					edit={edit.update}
					strings={(l) => ({
						placeholder: edit.placeholder(l)
					})}
				></EditableText>{:else}{revisedTitle}{/if}
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

	@keyframes wobble {
		0%,
		100% {
			transform: translateX(0);
		}
		20% {
			transform: translateX(-5px);
		}
		40% {
			transform: translateX(5px);
		}
		60% {
			transform: translateX(-3px);
		}
		80% {
			transform: translateX(3px);
		}
	}

	.wobble {
		animation: wobble 0.8s ease-in-out 0.3s 3;
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
