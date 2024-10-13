<script lang="ts">
	export let error = false;
</script>

<p class:error><slot /></p>

<style>
	p {
		margin-top: 0;
		background: var(--salient-color);
		color: var(--background-color);
		font-size: var(--small-font-size);
		padding: var(--spacing);
		border-radius: var(--roundedness);
	}

	.error {
		background: var(--error-color);
		font-weight: normal;
	}
</style>
