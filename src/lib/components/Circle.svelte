<script lang="ts">
	let {
		icon: count
	}: {
		icon: number | string;
	} = $props();
</script>

<div class="count">
	<div class="icon">
		{typeof count === 'string' ? count.replaceAll('\uFE0F', '') + '\uFE0E' : count}
	</div>
</div>

<style>
	.count {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		border-radius: 3em;
		padding: var(--spacing);
		background: var(--salient-color);
		color: var(--background-color);
		min-width: 1em;
		height: 1em;
		font-size: var(--small-font-size);
		align-self: start;
	}
</style>
