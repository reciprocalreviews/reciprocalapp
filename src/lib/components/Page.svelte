<script lang="ts">
	import { type Result } from '$lib/data/CRUD';
	import type LocaleText from '$lib/locales/Locale';
	import { getLocaleContext } from '$routes/Contexts';
	import { onMount, type Snippet } from 'svelte';
	import EditableText from './EditableText.svelte';
	import Lead from './Lead.svelte';
	import measure from './measure';

	let {
		icon = '',
		title,
		subtitle,
		details,
		children,
		wobble = false,
		edit
	}: {
		icon?: string | Snippet;
		title: string | ((l: LocaleText) => string);
		subtitle?: Snippet;
		details?: Snippet;
		children: Snippet;
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

	// Smoothly scroll the URL's hash target into the center of the viewport,
	// both on initial load and whenever the hash changes (e.g., a Subheader
	// anchor is clicked).
	function scrollToHash() {
		const hash = window.location.hash.slice(1);
		if (!hash) return;
		const el = document.getElementById(decodeURIComponent(hash));
		if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
	}

	onMount(() => {
		// Defer the initial scroll a frame so child Subheaders are mounted
		// and laid out before we measure their position.
		requestAnimationFrame(scrollToHash);
		window.addEventListener('hashchange', scrollToHash);
		return () => window.removeEventListener('hashchange', scrollToHash);
	});
</script>

<svelte:head>
	<title>{revisedTitle}</title>
</svelte:head>

<!--
	The page's title band, rendered here in flow rather than pushed up into the nav's
	sticky header through context. An `$effect` does not run during SSR, and the root
	layout renders `<Nav>` before its children, so a title sent upward could not reach
	the server HTML at all: it arrived at hydration and shoved `<main>` down every
	load, and collapsed and regrew on every client-side navigation. Rendered here it
	is server-rendered in document order, so the first paint is the final layout, and
	it still pins below the nav via the measured `--nav-height`. It also belongs in
	`main` rather than inside the banner landmark, where the page's `h1` used to sit.
-->
<div class="page-header" use:measure={'--page-header-height'}>
	<h1 class="page-header-title" class:wobble data-testid="page-header">
		<!-- The header is baseline-aligned (.page-header-title beats the h1 rule
		     below it), and an svg has no baseline of its own — it would align by
		     its bottom edge and tower over the text. The span supplies one. -->
		{#if typeof icon === 'string'}
			<span class="emoji">{icon}</span>
		{:else}
			<span class="mark">{@render icon()}</span>
		{/if}
		{#if edit}
			<EditableText
				text={revisedTitle}
				valid={edit.valid}
				edit={edit.update}
				strings={(l) => ({ placeholder: edit!.placeholder(l) })}
				testid="page-title-edit"
			/>
		{:else}
			{revisedTitle}
		{/if}
	</h1>
	{#if subtitle || details}
		<div class="details">
			{#if subtitle}<Lead>{@render subtitle()}</Lead>{/if}
			{@render details?.()}
		</div>
	{/if}
</div>

<section class="page">
	<div class="content">
		{@render children()}
	</div>
</section>

<style>
	.page-header {
		/* Pinned below the nav, which is sticky at the top of the viewport. Its height
		   varies with banners and row wrapping, so it is measured rather than guessed;
		   the fallback covers the first paint and a scripting-off reader. The nav keeps
		   a higher z-index, so it wins if this offset is ever momentarily stale. */
		position: sticky;
		top: var(--nav-height, 8rem);
		z-index: 1;

		/* Deliberately the full width of `main`, not the text column: the h1 is a
		   full-bleed band whose bottom corners are rounded against the nav above it.
		   `--page-width` is applied to `.page` below instead. */
		width: 100%;
		display: flex;
		flex-direction: column;
		gap: var(--spacing-half);
		padding-top: 0;
		background: var(--background-color);
		overflow-x: clip;
	}

	.page-header-title {
		align-items: baseline;
	}

	.emoji {
		font-family: 'Noto Emoji', 'Josefin Sans', sans-serif;
		font-size: 80%;
		/* A flex item; without this a long title squeezes the icon. */
		flex: none;
	}

	.mark {
		/* Full size, unlike .emoji's 80%: the logo's strokes are thinner than an
		   emoji glyph's, so at 80% it reads lighter than the wordmark beside it. */
		font-size: 100%;
		line-height: 1;
		flex: none;
	}

	h1 {
		display: flex;
		gap: 0.5rem;
		align-items: center;
		margin: 0;
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

	@media (prefers-reduced-motion: reduce) {
		.wobble {
			animation: none;
		}
	}

	.details {
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
		align-items: baseline;
		font-size: var(--small-font-size);
		padding-left: calc(var(--spacing) / 2);
		padding-right: calc(var(--spacing) / 2);
		padding-bottom: calc(var(--spacing) / 2);
		border-block-end: var(--border-color) solid var(--border-width);
	}

	.page {
		display: flex;
		flex-direction: column;
		gap: calc(2 * var(--spacing));
		width: 100%;
		/* The text column's cap, which used to sit on `main`. It moved down here so
		   that `main` — and therefore the title band above — can span the viewport. */
		max-width: var(--page-width);
		margin-inline: auto;
	}

	.page > :global(p) {
		margin-block-end: 0;
	}

	.content {
		display: flex;
		flex-direction: column;
		gap: calc(2 * var(--spacing));
		padding-left: calc(var(--spacing) * 2);
		padding-right: calc(var(--spacing) * 2);
	}
</style>
