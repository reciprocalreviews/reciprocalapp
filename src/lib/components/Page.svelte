<script lang="ts">
	import { type Result } from '#lib/data/CRUD.js';
	import type LocaleText from '#lib/locales/Locale.js';
	import { getLocaleContext } from '$routes/Contexts';
	import { onMount, type Snippet } from 'svelte';
	import EditableText from './EditableText.svelte';
	import Lead from './Lead.svelte';

	let {
		title,
		context,
		subtitle,
		details,
		actions,
		alerts,
		children,
		edit
	}: {
		title: string | ((l: LocaleText) => string);
		/**
		 * What the page belongs to, for the browser tab only: "Submissions" inside a venue is
		 * "Submissions — ToK" in a tab bar of several venues, where the venue bar that names
		 * it on the page is not visible. The heading stays the title alone.
		 */
		context?: string;
		/**
		 * What KIND of thing the title names — "Scholar", "Currency", a submission's type —
		 * and only on a page whose title is a proper name. A page titled by what it is
		 * ("Venues", "Submissions") has nothing to add, and its owner is the context bar's to say, not a subtitle's.
		 */
		subtitle?: Snippet;
		details?: Snippet;
		/**
		 * What the viewer can go and do from here: a row of `Action`s, and the occasional
		 * `Button` for a tool that acts in place. Participant actions first, role tools after.
		 */
		actions?: Snippet;
		/**
		 * `Alert`s about the current state, and only conditional ones — see Alert.svelte.
		 * Rendered after the actions, so an alert's own action can point at a tool the row
		 * above already offers without the two competing for first place.
		 */
		alerts?: Snippet;
		children: Snippet;
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
	let tabTitle = $derived(context ? `${revisedTitle} — ${context}` : revisedTitle);

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
	<title>{tabTitle}</title>
</svelte:head>

<!--
	Every page's title renders in the text column with the paragraphs it introduces. It used
	to be a full-bleed sticky band everywhere but inside a venue, where the venue bar takes
	that place; so one app had two heading treatments, and the band's details row read as a
	second row of navigation. The only sticky chrome now is the nav, and the venue bar
	inside a venue, which is the only writer of `--page-header-height`.
-->
<section class="page">
	<div class="content">
		<div class="page-heading">
			<h1 class="page-header-title" data-testid="page-header">
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
		<!-- The page's anatomy, in a fixed order on every page: what this is (above), what
		     you can do here, what needs your attention, and then the page itself. -->
		{#if actions}
			<div class="actions" data-testid="page-actions">{@render actions()}</div>
		{/if}
		{#if alerts}
			<div class="alerts" data-testid="page-alerts">{@render alerts()}</div>
		{/if}
		{@render children()}
	</div>
</section>

<style>
	.page-header-title {
		align-items: baseline;
	}

	/* An editable title's pencil sits beside the FIRST line of the title, not stretched
	   down the side of it. `EditableText` aligns its inline variant to `stretch`, which is
	   right for the one-line fields it was built for and wrong for a heading: a submission
	   title runs to three lines in the text column, and the control grew into a teal bar
	   the height of the whole heading. Scoped to headings so every other inline editable
	   keeps the alignment it was tuned for. */
	.page-header-title :global(.editable.inline) {
		align-items: flex-start;
	}

	h1 {
		display: flex;
		gap: 0.5rem;
		align-items: center;
		margin: 0;
	}

	.page-heading {
		display: flex;
		flex-direction: column;
		gap: var(--spacing-half);
		padding-block-start: var(--spacing);
	}

	.details {
		display: flex;
		flex-direction: row;
		/* Wraps: this row is metadata — a submission's type, manuscript ID and status — and
		   on a phone those do not fit side by side. */
		flex-wrap: wrap;
		gap: var(--spacing);
		align-items: baseline;
		font-size: var(--small-font-size);
	}

	.actions {
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		align-items: baseline;
		gap: var(--spacing-half);
	}

	/* A zone whose children are all conditional can render with nothing in it, and an empty
	   flex item still costs the column a gap. `:has` rather than `:empty`, which the
	   whitespace and anchors a Svelte block leaves behind defeat. */
	.actions:not(:has(*)),
	.alerts:not(:has(*)) {
		display: none;
	}

	.alerts {
		display: flex;
		flex-direction: column;
		gap: var(--spacing-half);
	}

	.page {
		display: flex;
		flex-direction: column;
		gap: calc(2 * var(--spacing));
		width: 100%;
		/* The text column's cap. On `.page` rather than `main` so the bars of chrome above
		   it can span the viewport. */
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
