<script lang="ts">
	export let good = true;
</script>

<div class="status" class:good><slot /></div>

<style>
	.status {
		display: inline-block;
		background: var(--error-color);
		color: var(--background-color);
		padding: calc(var(--spacing) / 2);
		font-size: var(--small-font-size);
		white-space: nowrap;
		align-self: flex-start;
	}

	.good {
		background: var(--salient-color);
	}
</style>
