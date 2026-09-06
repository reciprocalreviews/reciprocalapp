<script lang="ts">
	import { goto, invalidate, invalidateAll } from '$app/navigation';
	import { page } from '$app/state';
	import { requiresAuth } from '$lib/auth/requiresAuth';
	import Footer from '$lib/components/Footer.svelte';
	import Nav from '$lib/components/Nav.svelte';
	import { setDB } from '$lib/data/CRUD';
	import getRealtimeChannel from '$lib/data/SupabaseRealtime';
	import { onMount } from 'svelte';
	import SupabaseAuth, { setAuth } from './Auth.svelte';
	import { setLocaleContext } from './Contexts';

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

	onMount(() => {
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
		// Watches `transactions`, not `tokens`. Both wake on exactly the same
		// events, because only a transaction can move a token — but `tokens` is one
		// row per token, so earning fifty of them woke this channel fifty times and
		// re-ran every load function on the page fifty times. A transaction is one
		// row however much it moves.
		const channel = getRealtimeChannel(
			`header-balance-${id}`,
			db.client,
			[
				{ table: 'transactions', filter: `from_scholar=eq.${id}` },
				{ table: 'transactions', filter: `to_scholar=eq.${id}` }
			],
			() => invalidateAll()
		).subscribe();
		return () => {
			channel.unsubscribe();
		};
	});

	// The trail shown in the nav, from whichever load supplied one. It used to be a
	// mutable context that `Page` wrote from an `$effect` — which never runs during
	// SSR, so the server rendered a nav with no trail and hydration inserted it.
	let breadcrumbs = $derived(page.data.breadcrumbs ?? []);
</script>

<Nav {tokens} {breadcrumbs}></Nav>
<main>
	{@render children()}
</main>
<Footer />

<style>
	main {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
		/* Absorb whatever height the page does not use, so the footer below is carried
		   to the bottom of the viewport rather than floating up to meet short content
		   (#156). Pairs with the flex column on `body` in app.html. */
		flex: 1;
		/* Deliberately full width, and deliberately no block-start margin. The page
		   title bar is a full-bleed band that sits flush beneath the nav, so the text
		   column's `--page-width` cap lives one level down, on `.page` in
		   Page.svelte. */
	}
</style>
