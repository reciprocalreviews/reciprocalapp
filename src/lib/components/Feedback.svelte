<script lang="ts">
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';

	const {
		error = false,
		inline = true,
		round = true,
		testid,
		text
	}: {
		error?: boolean;
		inline?: boolean;
		round?: boolean;
		testid?: string;
		text: (locale: LocaleText) => string | string[];
	} = $props();
</script>

{#snippet content()}
	<Text markdown path={text} />
{/snippet}

{#if inline}
	<span class={['feedback', 'inline', { error, round }]} data-testid={testid}
		>{@render content()}</span
	>
{:else}
	<p class={['feedback', { error, round }]} data-testid={testid}>{@render content()}</p>
{/if}

<style>
	p,
	span {
		border-left: calc(var(--thick-border-width) * 2) solid var(--salient-color);
		background: var(--salient-color-faded);
		color: var(--text-color);
		padding: var(--spacing-half);
		padding-left: var(--spacing);
		font-size: var(--small-font-size);
	}

	p {
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

	.round {
		border-radius: var(--roundedness);
	}
</style>
