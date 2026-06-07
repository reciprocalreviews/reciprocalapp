<script lang="ts">
	import type LocaleText from '$lib/locales/Locale';
	import type { ButtonText } from '$lib/locales/Locale';
	import type { Snippet } from 'svelte';
	import Button from './Button.svelte';

	let {
		level,
		children,
		action = undefined,
		dismiss = undefined,
		detail = undefined,
		testid = undefined
	}: {
		/** Determines the banner's color. */
		level: 'beta' | 'update' | 'error' | 'warning' | 'success';
		/** The banner body (text and links). */
		children: Snippet;
		/** An optional action button (e.g. refresh). */
		action?: { strings: (locale: LocaleText) => ButtonText; do: () => void };
		/** An optional dismiss handler; when set, a dismiss button is shown. */
		dismiss?: () => void;
		/** An optional monospace detail line (e.g. a database error message). */
		detail?: string;
		testid?: string;
	} = $props();
</script>

<div class="banner {level}" role={level === 'error' ? 'alert' : 'status'} data-testid={testid}>
	<div class="body">
		<span>{@render children()}</span>
		{#if detail}
			<div class="detail">{detail}</div>
		{/if}
	</div>
	{#if action}
		<Button action={action.do} strings={action.strings} />
	{/if}
	{#if dismiss}
		<Button action={dismiss} strings={(l) => l.component.notification.dismiss} />
	{/if}
</div>

<style>
	.banner {
		display: flex;
		flex-direction: row;
		align-items: baseline;
		gap: var(--spacing);
		padding: var(--spacing);
		color: var(--background-color);
		border-block-end: var(--border-width) solid var(--border-color);
	}

	.body {
		display: flex;
		flex-direction: column;
		gap: var(--spacing-half);
	}

	.banner :global(a) {
		color: var(--background-color);
	}

	.banner :global(a .underline) {
		text-decoration-color: var(--background-color);
	}

	/* The action and dismiss buttons sit at the far end of the bar. */
	.banner :global(button) {
		margin-inline-start: auto;
	}

	.banner :global(button ~ button) {
		margin-inline-start: var(--spacing);
	}

	.beta,
	.success {
		background: var(--error-color);
	}

	.update,
	.warning {
		background: var(--focus-color);
	}

	.error {
		background: var(--error-color);
	}

	.detail {
		font-family: monospace;
		font-size: var(--small-font-size);
	}
</style>
