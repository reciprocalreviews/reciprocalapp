<script lang="ts">
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';

	const {
		error = false,
		warning = false,
		inline = true,
		round = true,
		size = 'small',
		testid,
		text
	}: {
		error?: boolean;
		/** Something to be careful about, as distinct from something that has gone
		 * wrong. Takes the focus colour, which is what Banner already uses for its
		 * warning level; `error` wins if both are set. */
		warning?: boolean;
		inline?: boolean;
		round?: boolean;
		size?: 'small' | 'normal';
		testid?: string;
		text: (locale: LocaleText) => string | string[];
	} = $props();
</script>

{#snippet content()}
	<Text markdown path={text} />
{/snippet}

{#if inline}
	<span
		class={['feedback', 'inline', size, { error, warning: warning && !error, round }]}
		data-testid={testid}>{@render content()}</span
	>
{:else}
	<div
		class={['feedback', size, { error, warning: warning && !error, round }]}
		data-testid={testid}
	>
		{@render content()}
	</div>
{/if}

<style>
	div,
	span {
		border-left: var(--thick-border-width) solid var(--salient-color);
		background: var(--salient-color-faded);
		color: var(--text-color);
		padding: var(--spacing-half);
		padding-left: var(--spacing);
	}

	.small {
		font-size: var(--small-font-size);
	}

	.normal {
		font-size: var(--paragraph-font-size);
	}

	div {
		margin-top: 0;
	}

	.inline {
		display: inline-block;
		align-self: flex-start;
	}

	.error {
		border-left-color: var(--error-color);
		background: var(--error-color-faded);
		color: var(--error-color);
	}

	.warning {
		border-left-color: var(--focus-color);
		background: var(--focus-color-faded);
		color: var(--focus-color);
	}

	.round {
		border-radius: var(--roundedness);
	}
</style>
