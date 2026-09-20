<script lang="ts">
	import { BETA } from '$lib/constants';
	import { dismissBeta } from '$lib/data/betaDismissal';
	import Text from '$lib/locales/Text.svelte';
	import Banner from './Banner.svelte';
	import measure from './measure';
	import Link from './Link.svelte';

	let {
		/** Whether the reader already put the beta notice away, read from a cookie by the
		 * root load so a dismissed notice is absent from the server HTML rather than
		 * flickering away at hydration. */
		betaDismissed = false
	}: { betaDismissed?: boolean } = $props();

	/** Hides the notice for this page immediately. The cookie is what makes it stick, but
	 * the load data behind `betaDismissed` is stale until the next `invalidateAll()`, so
	 * the local flag is what answers the click. Same shape as `updateDismissed` in
	 * Banners.svelte. */
	// svelte-ignore state_referenced_locally
	let dismissed = $state(betaDismissed);
</script>

<!-- Help and Contact come first among the outbound links: the footer is where someone
     who is stuck looks, and until now it offered them only a GitHub issue tracker. The
     issue tracker is still reachable, from /contact, where it is labeled for the people
     it actually suits. -->
<footer>
	<!-- The beta notice, which used to head the banner stack inside the sticky header. It
	     was true and useful once and then charged every page a band of the viewport
	     forever (#176). Pinned to the bottom of the viewport rather than to the bottom of
	     the document: at the end of a long page it was never seen, which is no way to run
	     a notice that asks for feedback. It can still be put away for good.

	     Still a child of <footer> though it is fixed, so "in the footer, not the header"
	     stays a true thing to assert about it. -->
	{#if BETA && !dismissed}
		<div class="beta" use:measure={'--bottom-chrome'}>
			<Banner
				level="beta"
				small
				testid="banner-beta"
				dismiss={() => {
					dismissed = true;
					dismissBeta();
				}}
			>
				<Text markdown path={(l) => l.banner.beta.lead} />
			</Banner>
		</div>
	{/if}
	<div class="links">
		<Link size="extra-small" to="/about"><Text path={(l) => l.footer.link.about} /></Link>
		<Link size="extra-small" to="/help"><Text path={(l) => l.footer.link.help} /></Link>
		<Link size="extra-small" to="/contact"><Text path={(l) => l.footer.link.contact} /></Link>
		<Link size="extra-small" to="/terms"><Text path={(l) => l.footer.link.terms} /></Link>
		<Link size="extra-small" to="/updates"><Text path={(l) => l.footer.link.updates} /></Link>
		<Link size="extra-small" to="/brand"><Text path={(l) => l.footer.link.brand} /></Link>
	</div>
</footer>

<style>
	footer {
		display: flex;
		flex-direction: column;
		gap: 0;
		margin-block-start: var(--spacing);
		border-block-start: var(--border-color) solid var(--border-width);
		background: var(--background-color);
		/* Room for the pinned notice, so it never covers these links.
		
		   On the footer rather than on `main`: `body` is a `min-height: 100dvh` flex column
		   with `main { flex: 1 }`, so on a short page `main` absorbs the slack and the
		   footer is ALREADY at the viewport bottom — padding inside `main` would not move it
		   out from under the bar. This is half of the pair #156 deleted; the other half is
		   `scroll-padding-block-end` in app.html. */
		padding-block-end: var(--bottom-chrome, 0px);
		/* Not sticky. It used to be, and on a short page — or on mobile the moment the
		   URL bar hides and the viewport grows — its natural position ended up above
		   the bottom edge and it appeared to float mid-screen (#156). The flex column
		   on `body` keeps it at the bottom without pinning it over the content.

		   `fixed` cannot recur that failure, because it is anchored to the viewport
		   unconditionally rather than only while content remains below it. What it CAN do is
		   occlude, which is what the padding above and the scroll padding in app.html are
		   for — the same pair, and for the same reason, as the ones #156 retired. */
	}

	.beta {
		position: fixed;
		bottom: 0;
		/* `inset-inline`, not `width: 100vw`: the viewport unit includes the scrollbar, and
		   a bar wider than the document gives the page a horizontal scrollbar — which on a
		   page with sticky rows slides the chrome itself out of view (#156). */
		inset-inline: 0;
		/* Above the nav's 2 and below the hydration notice's 100 in app.html. A modal
		   `<dialog>` uses showModal(), so the top layer covers this whatever the value —
		   which is right: the notice should not sit over a dialog. */
		z-index: 3;
		/* A no-op today, because app.html's viewport meta has no `viewport-fit=cover`, and
		   correct the moment it does. */
		padding-bottom: env(safe-area-inset-bottom, 0px);
	}

	.links {
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		gap: var(--spacing);
		row-gap: var(--spacing);
		align-items: baseline;
		justify-content: center;
		padding: var(--spacing);
	}
</style>
