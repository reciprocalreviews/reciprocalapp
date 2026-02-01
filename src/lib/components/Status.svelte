<script lang="ts">
	export let good = true;
</script>

<span class="status" class:good><slot /></span>

<style>
	.status {
		background: var(--error-color);
		color: var(--background-color);
		padding: calc(var(--spacing) / 4) var(--spacing-half) calc(var(--spacing) / 4)
			var(--spacing-half);
		font-size: var(--small-font-size);
		border-radius: var(--roundedness);
		white-space: nowrap;
	}

	.good {
		background: var(--salient-color);
	}
</style>
