<script lang="ts">
	import type { Snippet } from 'svelte';

	let {
		action,
		tip,
		children,
		active = true,
		formaction = undefined,
		name = undefined,
		type = undefined,
		view = $bindable(undefined)
	}: {
		children: Snippet;
		action: (event: Event) => void;
		tip: string;
		active?: boolean;
		formaction?: string | undefined;
		name?: string | undefined;
		type?: 'submit' | undefined;
		view?: HTMLButtonElement | undefined;
	} = $props();
</script>

<button
	bind:this={view}
	{name}
	{formaction}
	{type}
	title={tip}
	aria-label={tip}
	disabled={!active}
	onclick={(event) => (active ? action(event) : null)}>{@render children()}</button
>

<style>
	button {
		font-family: var(--font-face);
		font-size: var(--small-font-size);
		border: var(--border-color);
		border-radius: var(--roundedness);
		padding: var(--spacing);
		background: var(--text-color);
		color: var(--background-color);
		cursor: pointer;
		white-space: nowrap;
	}

	button[disabled] {
		background: var(--inactive-color);
		cursor: auto;
	}

	button:focus {
		outline: var(--focus-color) solid var(--thick-border-width);
	}

	button:not(.inactive):hover {
		transform: scale(1.05);
	}
</style>
