<script lang="ts">
	let {
		icon: count
	}: {
		icon: number | string;
	} = $props();
</script>

<div class="count">{count}</div>

<style>
	.count {
		display: inline-block;
		border-radius: 3em;
		padding: var(--spacing);
		background: var(--salient-color);
		color: var(--background-color);
		min-width: 1em;
		min-height: 1em;
		text-align: center;
		line-height: 1;
		font-size: var(--small-font-size);
		align-self: start;
	}
</style>
