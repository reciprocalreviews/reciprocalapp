<script lang="ts">
	import type { Snippet } from 'svelte';

	let {
		header,
		children,
		full = false
	}: { full?: boolean; header: Snippet; children: Snippet } = $props();
</script>

<div class="table" class:full>
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
</div>

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

	.full {
		width: calc(100vw - 2em);
		margin-left: calc(-1 * (100vw - 2em - 100%) / 2);
	}
</style>
