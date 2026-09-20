<script lang="ts">
	import { page } from '$app/state';
	import type LocaleText from '$lib/locales/Locale';
	import type { ButtonText } from '$lib/locales/Locale';
	import { getLocaleContext } from '$routes/Contexts';
	import type { Snippet } from 'svelte';
	import { clickOutside } from './clickOutside';

	/**
	 * Links that stay in the row while there is room for them, and collapse behind one
	 * control when there is not.
	 *
	 * Both bands of chrome used `flex-wrap: wrap`, which meant a narrow screen answered a
	 * crowded row by growing a second one — so the fixed header took nearly half the
	 * viewport on a phone, which is the problem #176 is about.
	 *
	 * Three things about how this is built are load-bearing:
	 *
	 * 1. **A media query decides, not a measurement.** Measuring the row would mean
	 *    rendering the links, measuring after hydration, and then collapsing them — a
	 *    layout shift on every load, and the exact failure that `Page.svelte` and
	 *    `breadcrumbs.ts` both carry paragraphs about. A media query applies to the
	 *    server-rendered HTML at first paint, and the server never has to guess a width.
	 *
	 * 2. **`display: contents` while wide.** The children are rendered once and flow
	 *    straight into the parent's flex row, so nothing is duplicated. A version that
	 *    rendered an inline copy and a menu copy would put two elements behind every test
	 *    id in the chrome.
	 *
	 * 3. **The panel is absolutely positioned.** `Nav.svelte`'s measured height feeds
	 *    `--nav-height`, which is the sticky offset for everything below it. A panel that
	 *    took part in layout would move the whole page down when opened.
	 *
	 * `<details>` was the obvious alternative and cannot do (2): its content is hidden when
	 * closed, and revealing it only at wide widths needs `::details-content`, which is not
	 * yet baseline. A `popover` handles (3) natively but needs CSS anchor positioning to sit
	 * under its own button, which is still landing in Safari and Firefox.
	 *
	 * The tradeoff, stated rather than discovered: with scripting off on a narrow screen the
	 * collapsed links cannot be reached. Only secondary links collapse, and the app already
	 * needs hydration to do anything at all.
	 */
	let {
		strings,
		testid = undefined,
		children
	}: {
		/** Names the control for a screen reader — "Site menu", "Venue menu". */
		strings: (l: LocaleText) => ButtonText;
		testid?: string;
		children: Snippet;
	} = $props();

	const locale = getLocaleContext();
	const text = $derived(strings(locale()));

	let open = $state(false);

	/**
	 * Close on navigation, so following a link out of the menu does not leave it hanging
	 * open over the page that arrives.
	 *
	 * An `$effect` in chrome, which this codebase is otherwise careful about — but this one
	 * is the safe kind. It cannot run during SSR, it only ever closes a menu that a reader
	 * opened after hydration, and it writes no layout, so there is nothing for the server
	 * and the client to disagree about.
	 */
	$effect(() => {
		page.url.pathname;
		open = false;
	});
</script>

<!-- Escape on the window rather than on the wrapper, so it closes the menu wherever focus
     has got to inside the open panel — and so the wrapper stays a plain container with no
     interaction handler and no invented ARIA role to justify one. -->
<svelte:window
	onkeydown={(event) => {
		if (event.key === 'Escape' && open) open = false;
	}}
/>

<div class="overflow" class:open use:clickOutside={() => (open = false)}>
	<button
		type="button"
		class="toggle"
		aria-expanded={open}
		title={text.tip}
		aria-label={text.tip}
		data-testid={testid}
		onclick={() => (open = !open)}>☰</button
	>
	<div class="panel">{@render children()}</div>
</div>

<style>
	/* Wide: no box of its own. The children become flex items of whichever row this sits
	   in, exactly as if this component were not here. */
	.overflow {
		display: contents;
	}

	.toggle {
		display: none;
	}

	/* The one width breakpoint this project has, besides the 30rem in ORCIDProfile.svelte.
	   48rem is the conventional tablet line and comfortably wider than that one, because
	   these rows carry more than a two-column definition list. It is written literally
	   because a custom property cannot be used inside a media query — so if a third
	   breakpoint ever appears, these are the two places to reconcile. */
	@media (max-width: 48rem) {
		.overflow {
			display: flex;
			position: relative;
		}

		.toggle {
			display: inline-block;
			font-family: var(--font-face);
			font-size: var(--small-font-size);
			line-height: 1;
			cursor: pointer;
			background: var(--salient-color-faded);
			color: var(--foreground-color);
			border: none;
			border-radius: var(--roundedness);
			padding: var(--spacing-half);
		}

		.toggle:focus {
			outline: var(--focus-color) solid var(--thick-border-width);
		}

		.panel {
			display: none;
			position: absolute;
			top: 100%;
			inset-inline-end: 0;
			z-index: 3;
			flex-direction: column;
			align-items: flex-start;
			gap: var(--spacing);
			white-space: nowrap;
			background: var(--background-color);
			border: var(--border-color) solid var(--border-width);
			border-radius: var(--roundedness);
			padding: var(--spacing);
			box-shadow: 2px 3px 0 rgba(0, 0, 0, 0.2);
		}

		.overflow.open .panel {
			display: flex;
		}
	}
</style>
