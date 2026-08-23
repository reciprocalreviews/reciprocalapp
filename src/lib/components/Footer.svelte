<script lang="ts">
	import Link from './Link.svelte';
	import Text from '$lib/locales/Text.svelte';
</script>

<!-- Help and Contact come first among the outbound links: the footer is where someone
     who is stuck looks, and until now it offered them only a GitHub issue tracker. The
     issue tracker is still reachable, from /contact, where it is labeled for the people
     it actually suits. -->
<footer>
	<Link size="extra-small" to="/about"><Text path={(l) => l.footer.link.about} /></Link>
	<Link size="extra-small" to="/help"><Text path={(l) => l.footer.link.help} /></Link>
	<Link size="extra-small" to="/contact"><Text path={(l) => l.footer.link.contact} /></Link>
	<Link size="extra-small" to="/terms"><Text path={(l) => l.footer.link.terms} /></Link>
	<Link size="extra-small" to="/updates"><Text path={(l) => l.footer.link.updates} /></Link>
	<Link size="extra-small" to="/brand"><Text path={(l) => l.footer.link.brand} /></Link>
</footer>

<style>
	footer {
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		gap: var(--spacing);
		row-gap: var(--spacing);
		align-items: baseline;
		justify-content: center;
		margin-block-start: var(--spacing);
		padding: var(--spacing);
		border-block-start: var(--border-color) solid var(--border-width);
		background: var(--background-color);

		/* The header is sticky */
		position: sticky;
		bottom: 0;
		z-index: 2;
	}
</style>
