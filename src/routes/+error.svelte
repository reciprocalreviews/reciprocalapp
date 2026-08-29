<script lang="ts">
	import { page } from '$app/state';
	import Feedback from '$lib/components/Feedback.svelte';
	import { ErrorLabel } from '$lib/components/Labels';
	import Page from '$lib/components/Page.svelte';

	// Until this file existed, every `error()` thrown from a load rendered SvelteKit's
	// bare fallback: no navigation, no branding, no locale. That is what /help/<slug>
	// has always done for a missing article, and what a 404 from any route would do.
	// This puts the app's own chrome around it.
	//
	// It lives at the root rather than under [[lang]] so it also catches errors thrown
	// by routes outside the locale prefix, and it renders inside +layout.svelte —
	// whose load succeeds even when a child's fails — so locale and nav are available.
	let missing = $derived(page.status === 404);
</script>

<Page
	icon={ErrorLabel}
	title={(l) => (missing ? l.page.error.missing : l.page.error.title)}
	breadcrumbs={[]}
>
	<Feedback error text={(l) => (missing ? l.page.error.notFound : l.page.error.unexpected)}
	></Feedback>
</Page>
