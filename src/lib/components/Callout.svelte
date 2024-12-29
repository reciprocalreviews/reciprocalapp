<script lang="ts">
	let { children } = $props();
</script>

<div class="callout">
	{@render children()}
</div>

<style>
	.callout {
		padding: var(--spacing);
		border-left: solid var(--thick-border-width) var(--border-color);
		border-radius: var(--roundedness);
		background-color: var(--alternating-color);
	}
</style>
