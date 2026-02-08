<script lang="ts">
	import Link from './Link.svelte';
</script>

<footer>
	<Link small to="/about">About</Link>
	<Link small to="https://github.com/reciprocalreviews/reciprocalapp/issues/">Feedback</Link>
</footer>

<style>
	footer {
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		gap: var(--spacing);
		row-gap: var(--spacing);
		align-items: baseline;
		justify-content: end;
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
