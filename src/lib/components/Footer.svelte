<script lang="ts">
	import Link from './Link.svelte';
	import Text from '$lib/locales/Text.svelte';
</script>

<footer>
	<Link size="extra-small" to="/about"><Text path={(l) => l.footer.link.about} /></Link>
	<Link size="extra-small" to="/updates"><Text path={(l) => l.footer.link.updates} /></Link>
	<Link size="extra-small" to="https://github.com/reciprocalreviews/reciprocalapp/issues/"
		><Text path={(l) => l.footer.link.feedback} /></Link
	>
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
