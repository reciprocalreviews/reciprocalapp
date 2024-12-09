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
		border-radius: 3em;
		padding: var(--spacing);
		background: var(--salient-color);
		color: var(--background-color);
		min-width: 1em;
		min-height: 1em;
		text-align: center;
		font-size: var(--small-font-size);
	}
</style>
