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
		font-weight: 400;
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
		outline: none;
		color: var(--focus-color);
	}

	a[aria-current] {
		color: var(--text-color);
	}
</style>
