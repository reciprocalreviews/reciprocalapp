<script lang="ts">
	import { beforeNavigate } from '$app/navigation';
	import { type Result } from '$lib/data/CRUD';
	import type LocaleText from '$lib/locales/Locale';
	import { getLocaleContext } from '$routes/Contexts';
	import type PageHeader from '$routes/PageHeader';
	import { getContext, onMount, type Snippet } from 'svelte';

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

	function cleanupContext() {
		pageHeader.icon = '';
		pageHeader.title = '';
		pageHeader.wobble = false;
		pageHeader.subtitle = undefined;
		pageHeader.details = undefined;
		pageHeader.edit = undefined;
	}

	beforeNavigate(({ from, to }) => {
		if (
			from &&
			to &&
			from.url.pathname === to.url.pathname &&
			from.url.search === to.url.search
		)
			return;
		cleanupContext();
	});

	const pageHeader = getContext<PageHeader>('pageHeader');
	$effect(() => {
		if (pageHeader) {
			pageHeader.icon = icon;
			pageHeader.title = revisedTitle;
			pageHeader.wobble = wobble;
			pageHeader.subtitle = subtitle;
			pageHeader.details = details;
			pageHeader.edit = edit;

			return () => {
				cleanupContext();
			};
		}
	});

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

<section class="page">
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
