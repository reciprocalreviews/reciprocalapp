<script lang="ts">
	export let active = true;
	export let formaction: string | undefined = undefined;
	export let action: () => void;
	export let name: string | undefined = undefined;
	export let type: 'submit' | undefined = undefined;
</script>

<button {name} {formaction} {type} disabled={!active} on:click={active ? action : null}
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

	button[disabled] {
		background: var(--inactive-color);
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
