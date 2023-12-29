<table>
	<tbody>
		<slot />
	</tbody>
</table>

<style>
	table {
		width: 100%;
		border-collapse: collapse;
		margin-block-start: var(--spacing);
		margin-block-end: var(--spacing);
	}

	table :global(td) {
		padding: var(--spacing);
		vertical-align: baseline;
	}

	table :global(tr:nth-child(even)) {
		background: var(--alternating-color);
	}
</style>
