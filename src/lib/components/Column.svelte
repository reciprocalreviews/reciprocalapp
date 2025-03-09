<script lang="ts">
	let { children } = $props();
</script>

<div class="column">{@render children()}</div>

<style>
	.column {
		display: flex;
		flex-direction: column;
		flex-wrap: nowrap;
		gap: var(--spacing);
		align-items: start;
	}
</style>
