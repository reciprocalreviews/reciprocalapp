<script lang="ts">
	let { children } = $props();
</script>

<div class="tip">
	<div class="bulb">?</div>
	<div class="content">{@render children()}</div>
</div>

<style>
	.tip {
		display: flex;
		flex-direction: row;
		flex-wrap: nowrap;
		gap: var(--spacing);
		align-items: baseline;
		font-size: var(--small-font-size);
		padding-left: var(--spacing);
		border-left: solid var(--thick-border-width) var(--border-color);
		border-radius: var(--roundedness);
	}
</style>
