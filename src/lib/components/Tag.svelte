<script lang="ts">
	import type { Snippet } from 'svelte';

	let {
		children,
		action = undefined,
		selected = false,
		wrap = false,
		testid = undefined
	}: {
		children: Snippet;
		/** When given, the tag is a toggle rather than a label — an expertise filter
		 * chip. Without it this renders exactly the span it always did. */
		action?: () => void;
		/** Whether that toggle is on. Only meaningful alongside `action`. */
		selected?: boolean;
		/** Let a long tag wrap. Tags are nowrap by default, which reads better for
		 * the short labels most of them are — but a tag is whatever text somebody
		 * typed, and one unbreakable box sets the minimum width of everything
		 * around it. In a table that is the whole table. */
		wrap?: boolean;
		testid?: string;
	} = $props();
</script>

{#if action}
	<button
		type="button"
		class="tag"
		class:selected
		class:wrap
		aria-pressed={selected}
		data-testid={testid}
		onclick={action}>{@render children()}</button
	>
{:else}
	<span class="tag" class:wrap data-testid={testid}>{@render children()}</span>
{/if}

<style>
	.tag {
		font-family: var(--font-face);
		background: var(--salient-color-faded);
		color: var(--foreground-color);
		padding: calc(var(--spacing) / 4) var(--spacing-half);
		border-radius: 0.5em;
		font-size: var(--extra-small-font-size);
		white-space: nowrap;
	}

	.wrap {
		white-space: normal;
		/* `anywhere` rather than `break-word`: an expertise entered as one long
		   unspaced string still has to be breakable, or it sets the floor by itself. */
		overflow-wrap: anywhere;
	}

	button.tag {
		margin: 0;
		/* Transparent rather than absent, so the hover border does not shift layout. */
		border: var(--border-width) solid transparent;
		line-height: inherit;
		cursor: pointer;
	}

	button.tag:hover {
		border-color: var(--salient-color);
	}

	button.tag.selected {
		background: var(--salient-color);
		color: var(--background-color);
	}

	button.tag:focus-visible {
		outline: var(--border-width) solid var(--focus-color);
		outline-offset: 2px;
	}
</style>
