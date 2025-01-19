<script lang="ts">
	import type { Snippet } from 'svelte';

	let { header, children }: { header: Snippet; children: Snippet } = $props();
</script>

<table>
	<thead>
		<tr>
			{@render header()}
		</tr>
	</thead>
	<tbody>
		{@render children()}
	</tbody>
</table>

<style>
	table {
		width: 100%;
		border-collapse: collapse;
		margin-block-start: var(--spacing);
		margin-block-end: var(--spacing);
		table-layout: auto;
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
</style>
