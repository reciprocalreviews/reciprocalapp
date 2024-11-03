<script lang="ts">
	export let inline = false;
</script>

<form class:inline><slot /></form>

<style>
	form {
		display: flex;
		flex-direction: column;
		align-items: left;
		gap: var(--spacing);
		align-items: flex-start;
	}

	form.inline {
		flex-direction: row;
		flex-wrap: wrap;
		gap: var(--spacing);
		row-gap: var(--spacing);
	}
</style>
