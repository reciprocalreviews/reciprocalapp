<script lang="ts">
	import { page } from '$app/state';
	import type { Snippet } from 'svelte';

	let {
		to,
		small = false,
		children
	}: { to: string; small?: boolean; children: Snippet } = $props();

	let inactive = $derived(page.url.pathname === to);
</script>

<a
	class:small
	href={inactive ? null : to}
	target={to.startsWith('http') ? '_blank' : null}
	aria-current={inactive ? 'page' : null}
	>{@render children()}{#if to.startsWith('http')}<sub>⏵</sub>{/if}</a
>

<style>
	a {
		color: var(--salient-color);
		font-weight: 500;
		text-decoration: none;
		font-size: inherit;
	}

	a.small {
		font-size: var(--small-font-size);
	}

	a:hover:not([aria-current]) {
		text-decoration: underline;
		text-decoration-thickness: var(--thick-border-width);
	}

	a:focus {
		outline: var(--focus-color) solid var(--thick-border-width);
		border-radius: var(--roundedness);
		outline-offset: var(--border-width);
	}

	a[aria-current] {
		color: var(--text-color);
	}
</style>
