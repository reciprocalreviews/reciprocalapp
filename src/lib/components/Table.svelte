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

	.full {
		width: calc(100vw - var(--spacing) * 2);
		margin-inline-start: calc(-1 * (100vw - min(100%, var(--page-width))) / 2 + var(--spacing));
	}
</style>
