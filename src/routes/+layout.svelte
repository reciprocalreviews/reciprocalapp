<script lang="ts">
	import { goto, invalidate, invalidateAll } from '$app/navigation';
	import { page } from '$app/state';
	import { PUBLIC_ENV } from '$env/static/public';
	import { requiresAuth } from '$lib/auth/requiresAuth';
	import Footer from '$lib/components/Footer.svelte';
	import Nav from '$lib/components/Nav.svelte';
	import { setDB } from '$lib/data/CRUD';
	import getRealtimeChannel from '$lib/data/SupabaseRealtime';
	import { onMount, setContext } from 'svelte';
	import SupabaseAuth, { setAuth } from './Auth.svelte';
	import { setLocaleContext } from './Contexts';
	import type PageHeader from './PageHeader';

	let { data, children } = $props();
	let { db, scholar, claims, locale, tokens } = $derived(data);

	// The raw Supabase client is reached only through the CRUD instance's
	// sanctioned `client` escape hatch (auth + realtime); see #137.
	let auth = $derived(new SupabaseAuth(db.client, scholar));

	setAuth(() => auth);

	setLocaleContext(() => locale);

	// Set client side database cache. The layout load already built the single
	// CRUD instance, so reuse it rather than constructing another.
	setDB(() => db);

	const inProd = PUBLIC_ENV === 'prod';

	/** Always go home in production, pre-release */
	onMount(() => {
		if (inProd && !['/updates', '/about'].some((p) => page.url.pathname.startsWith(p))) goto('/');

		// Listen to auth state changes and invalidate the auth context when they happen.
		const { data } = db.client.auth.onAuthStateChange((event, _session) => {
			if (_session?.expires_at !== claims?.exp) {
				invalidate('supabase:auth');
			}
			// When the session ends — token expiry, a failed refresh (e.g. the refresh token
			// was revoked or the local DB was reset), or sign-out — don't strand the scholar on
			// an authenticated page where every action fails with a cryptic RLS/permission
			// error. Send them to login instead. Public pages are exempt so anonymous browsing
			// and the marketing pages aren't disrupted.
			if (event === 'SIGNED_OUT' && requiresAuth(page.url.pathname)) {
				goto('/login');
			}
		});
		return () => data.subscription.unsubscribe();
	});

	// Keep the header's token balance live for changes made elsewhere — a minter
	// approving a mint, an editor completing your assignment — not just for the
	// scholar's own writes (which handle() already covers with invalidateAll).
	// An $effect rather than reloadOnChanges' onMount, because the layout never
	// remounts: signing in mid-session has to (re)subscribe for the new scholar.
	$effect(() => {
		const id = scholar?.id;
		if (id === undefined) return;
		const channel = getRealtimeChannel(
			`header-balance-${id}`,
			db.client,
			[{ table: 'tokens', filter: `scholar=eq.${id}` }],
			() => invalidateAll()
		).subscribe();
		return () => {
			channel.unsubscribe();
		};
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

<Nav {inProd} {tokens} breadcrumbs={breadcrumbs.breadcrumbs}></Nav>
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
		/* Keep the last of the page's content clear of the sticky footer, which would
		   otherwise sit directly on top of it. Pairs with the scroll-padding on `html`
		   in app.html: that governs where scrolling stops, this guarantees there is
		   somewhere to stop. */
		padding-block-end: 5rem;
	}
</style>
