<script lang="ts">
	import { goto, invalidate } from '$app/navigation';
	import { page } from '$app/state';
	import { PUBLIC_ENV } from '$env/static/public';
	import Footer from '$lib/components/Footer.svelte';
	import Nav from '$lib/components/Nav.svelte';
	import { setDB } from '$lib/data/CRUD';
	import SupabaseCRUD from '$lib/data/SupabaseCRUD.svelte';
	import { onMount, setContext } from 'svelte';
	import SupabaseAuth, { setAuth } from './Auth.svelte';
	import { setLocaleContext } from './Contexts';
	import type PageHeader from './PageHeader';

	let { data, children } = $props();
	let { supabase, scholar, claims, locale } = $derived(data);

	let auth = $derived(new SupabaseAuth(supabase, scholar));

	setAuth(() => auth);

	setLocaleContext(() => locale);

	let crud = $derived(new SupabaseCRUD(supabase, locale));

	// Set client side database cache.
	setDB(() => crud);

	const inProd = PUBLIC_ENV === 'prod';

	/** Always go home in production, pre-release */
	onMount(() => {
		if (inProd && !['/updates', '/about'].some((p) => page.url.pathname.startsWith(p))) goto('/');

		// Listen to auth stage changes and invalidate the auth context when they happen.
		const { data } = supabase.auth.onAuthStateChange((_, _session) => {
			if (_session?.expires_at !== claims?.exp) {
				invalidate('supabase:auth');
			}
		});
		return () => data.subscription.unsubscribe();
	});

	// This global state stores breadcrumb data. The Page component sets it.
	let breadcrumbs = $state<{ breadcrumbs: [string, string][] }>({ breadcrumbs: [] });

	setContext('breadcrumbs', breadcrumbs);

	let pageHeader = $state<PageHeader>({
		icon: '',
		title: '',
		wobble: false,
		subtitle: undefined,
		details: undefined,
		edit: undefined
	});

	setContext('pageHeader', pageHeader);
</script>

{#if !inProd}
	<Nav breadcrumbs={breadcrumbs.breadcrumbs}></Nav>
{/if}
<main>
	{@render children()}
</main>
<Footer />

<style>
	main {
		margin-block-start: var(--spacing);
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
		margin: auto;
		max-width: var(--page-width);
	}
</style>
