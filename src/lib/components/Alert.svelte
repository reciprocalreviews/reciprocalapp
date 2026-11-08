<script lang="ts">
	import type { Html } from '#lib/locales/html.js';
	import type LocaleText from '#lib/locales/Locale.js';
	import Text from '#lib/locales/Text.svelte';
	import type { Snippet } from 'svelte';

	/**
	 * Something about the current state that needs the viewer's attention, in a page's
	 * alerts zone.
	 *
	 * An alert is conditional by definition: it appears because some state makes it true
	 * and goes away when that state is resolved. A notice that shows on every visit to
	 * everyone in a role is not one — that is an action (when it links to a tool) or help
	 * (when it explains), and putting it here teaches people to stop reading this zone.
	 *
	 * The tone says what kind of state it is, not how loud to be:
	 * - `problem`: something is broken or blocked.
	 * - `attention`: the state needs someone to act.
	 * - `info`: worth knowing, and nobody's fault.
	 */
	let {
		tone,
		text,
		inputs = {},
		testid,
		action,
		children
	}: {
		tone: 'problem' | 'attention' | 'info';
		text: (l: LocaleText) => string | string[];
		inputs?: Record<string, string | Html>;
		testid?: string;
		/** The one thing to do about it, usually an `Action` or a `Button`. */
		action?: Snippet;
		/** Detail below the message, such as the list of what is blocking. */
		children?: Snippet;
	} = $props();
</script>

<div class="alert {tone}" role={tone === 'problem' ? 'alert' : 'status'} data-testid={testid}>
	<div class="message"><Text markdown path={text} {inputs} /></div>
	{@render children?.()}
	{#if action}<div class="act">{@render action()}</div>{/if}
</div>

<style>
	/* The same family as Feedback — left rule on a faded ground — so a page's alerts and
	   its inline results read as one vocabulary, distinguished by tone rather than shape. */
	.alert {
		display: flex;
		flex-direction: column;
		gap: var(--spacing-half);
		border-left: var(--thick-border-width) solid var(--salient-color);
		background: var(--salient-color-faded);
		color: var(--text-color);
		padding: var(--spacing-half);
		padding-left: var(--spacing);
		border-radius: var(--roundedness);
		font-size: var(--small-font-size);
	}

	.attention {
		border-left-color: var(--focus-color);
		background: var(--focus-color-faded);
	}

	.problem {
		border-left-color: var(--error-color);
		background: var(--error-color-faded);
		color: var(--error-color);
	}

	.message :global(p) {
		margin: 0;
	}

	.act {
		display: flex;
		flex-wrap: wrap;
		gap: var(--spacing-half);
	}
</style>
