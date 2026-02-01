<script lang="ts">
	import { page } from '$app/state';
	import type { Snippet } from 'svelte';

	let {
		to,
		small = false,
		background = false,
		underline = true,
		icon = null,
		children
	}: {
		to: string;
		small?: boolean;
		background?: boolean;
		underline?: boolean;
		icon?: string | null;
		children: Snippet;
	} = $props();

	let inactive = $derived(page.url.pathname === to);
</script>

<a
	class:small
	class:background
	class:inactive
	href={inactive ? null : to}
	target={to.startsWith('http') ? '_blank' : null}
	aria-current={inactive ? 'page' : null}
	><span class:underline>{@render children()}</span>{#if to.startsWith('http')}<sub>🌐</sub
		>{/if}{#if icon}<sub>{icon}</sub>{/if}</a
>

<style>
	a {
		color: var(--salient-color);
		font-weight: 400;
		text-decoration: none;
		white-space: wrap;
	}

	a .underline {
		text-decoration: underline var(--salient-color) var(--thick-border-width) solid;
		text-decoration-skip-ink: none;
	}

	a.small,
	.background {
		font-size: var(--small-font-size);
	}

	a span:hover:not([aria-current]) {
		text-decoration: underline;
		text-decoration-thickness: calc(1.25 * var(--thick-border-width));
	}

	a:focus {
		outline: none;
		color: var(--focus-color);
	}

	a[aria-current] {
		color: var(--text-color);
		text-decoration: none;
	}

	.inactive span,
	.inactive span:hover:not([aria-current]) {
		text-decoration: none;
	}

	.background {
		background-color: var(--salient-color-faded);
		padding: var(--spacing-half);
		border-radius: var(--roundedness);
		color: var(--text-color);
	}
</style>
