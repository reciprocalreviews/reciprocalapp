<script lang="ts">
	import { BETA } from '$lib/constants';
	import { dismissBeta } from '$lib/data/betaDismissal';
	import Text from '$lib/locales/Text.svelte';
	import Banner from './Banner.svelte';
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
	     forever (#176). Down here it is still on every page, still says the same thing,
	     and costs nothing above the fold — and it can be put away for good. -->
	{#if BETA && !dismissed}
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
		/* Not sticky. It used to be, and on a short page — or on mobile the moment the
		   URL bar hides and the viewport grows — its natural position ended up above
		   the bottom edge and it appeared to float mid-screen (#156). The flex column
		   on `body` keeps it at the bottom without pinning it over the content.

		   That is also why the beta notice is safe here and was not safe in the header:
		   nothing measures this element, so nothing moves when it is dismissed. */
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
