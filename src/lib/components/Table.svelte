<script lang="ts">
	import type { Snippet } from 'svelte';

	let {
		header = undefined,
		children,
		full = false
	}: { full?: boolean; header?: Snippet; children: Snippet } = $props();
</script>

<div class="table" class:full>
	<table>
		{#if header}
			<thead>
				<tr>
					{@render header()}
				</tr>
			</thead>
		{/if}
		<tbody>
			{@render children()}
		</tbody>
	</table>
</div>

<style>
	.table {
		/* Scroll a wide table inside itself rather than letting it widen the document.
		   `width: 100%` under `table-layout: auto` is a floor, not a ceiling: a table
		   with many columns or a long unbroken string grows past its container, and a
		   document wider than the viewport slides the sticky nav sideways out of view,
		   because sticky only offsets on the axis it is given an inset for (#156). */
		overflow-x: auto;
	}

	table {
		width: 100%;
		border-collapse: collapse;
		margin: 0;
		table-layout: auto;
		border: solid var(--border-color) var(--border-width);
	}

	thead tr {
		border-bottom: var(--border-color) solid var(--border-width);
	}

	table :global(td) {
		padding-top: var(--spacing);
		padding-bottom: var(--spacing);
		padding-right: var(--spacing);
		vertical-align: baseline;
	}

	table :global(tr:nth-child(even)) {
		background: var(--alternating-color);
	}

	/* A full-bleed table has the whole viewport but also the most columns, and
	   every cell pays 1rem of padding on each side from the global td/th rule in
	   app.html — 8rem of padding across four columns before any content. Halving
	   it here buys back the width that was pushing the last column out of view. */
	.full table :global(td),
	.full table :global(th) {
		padding-left: var(--spacing-half);
		padding-right: var(--spacing-half);
	}

	.full {
		width: calc(100vw - var(--spacing) * 2);
		margin-inline-start: calc(-1 * (100vw - min(100%, var(--page-width))) / 2 + var(--spacing));
	}
</style>
