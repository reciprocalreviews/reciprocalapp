<script lang="ts">
	import { page } from '$app/state';
	import type { Snippet } from 'svelte';

	let {
		to,
		size = 'normal',
		background = false,
		underline = true,
		icon = null,
		testid,
		children
	}: {
		to: string;
		size?: 'small' | 'normal' | 'extra-small';
		background?: boolean;
		underline?: boolean;
		icon?: string | null;
		testid?: string;
		children: Snippet;
	} = $props();

	let inactive = $derived(page.url.pathname === to);
</script>

<a
	class={size}
	class:background
	class:inactive
	href={inactive ? null : to}
	target={to.startsWith('http') ? '_blank' : null}
	aria-current={inactive ? 'page' : null}
	data-testid={testid}
	><span class:underline>{@render children()}</span>{#if to.startsWith('http')}<sub class="cling"
			>🌐</sub
		>{/if}{#if icon}<sub class="cling">{icon}</sub>{/if}</a
>

<style>
	a {
		text-decoration: none;
	}

	/* A Word Joiner (U+2060) prepended via a pseudo-element is a zero-width
	   character that prohibits line-breaking at its position. This keeps
	   trailing icons glued to the preceding link text so the icon can never
	   wrap to a line of its own. */
	.cling::before {
		content: '\2060';
	}

	a .underline {
		text-decoration: underline var(--salient-color) var(--thick-border-width) solid;
		text-decoration-skip-ink: none;
	}

	a.small,
	.background {
		font-size: var(--small-font-size);
	}

	a.extra-small {
		font-size: var(--extra-small-font-size);
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
