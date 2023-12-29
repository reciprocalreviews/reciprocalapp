<script lang="ts">
	export let submit = false;
	export let active = true;
	export let action: () => void;
</script>

<button class:inactive={!active} type={submit ? 'submit' : null} on:click={active ? action : null}
	><slot /></button
>

<style>
	button {
		font-family: var(--font-face);
		font-size: var(--small-font-size);
		border: var(--border-color);
		border-radius: var(--roundedness);
		padding: var(--spacing);
		background: var(--salient-color);
		color: var(--background-color);
		cursor: pointer;
		white-space: nowrap;
	}

	button.inactive {
		background: var(--border-color);
		cursor: auto;
	}

	button:focus {
		outline: none;
		background: var(--focus-color);
	}

	button:not(.inactive):hover {
		transform: scale(1.05);
	}
</style>
