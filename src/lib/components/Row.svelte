<script lang="ts">
	let { children } = $props();
</script>

<div class="row">{@render children()}</div>

<style>
	.row {
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		gap: var(--spacing);
		row-gap: var(--spacing);
		align-items: center;
	}
</style>
