<script lang="ts">
	export let inline = false;
</script>

<form class:inline><slot /></form>

<style>
	form {
		display: flex;
		flex-direction: column;
		gap: calc(2 * var(--spacing));
		align-items: flex-start;
	}

	form.inline {
		flex-direction: row;
		flex-wrap: wrap;
		align-items: baseline;
		gap: var(--spacing);
		row-gap: var(--spacing);
	}
</style>
