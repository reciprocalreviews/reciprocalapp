<script lang="ts">
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';

	const {
		error = false,
		inline = true,
		testid,
		text
	}: {
		error?: boolean;
		inline?: boolean;
		testid?: string;
		text: (locale: LocaleText) => string | string[];
	} = $props();
</script>

{#snippet content()}
	<Text markdown path={text} />
{/snippet}

{#if inline}
	<span class={['feedback', 'inline', { error }]} data-testid={testid}>{@render content()}</span>
{:else}
	<p class={['feedback', { error }]} data-testid={testid}>{@render content()}</p>
{/if}

<style>
	p,
	span {
		border-left: calc(var(--thick-border-width) * 2) solid var(--salient-color);
		background: var(--salient-color-faded);
		padding: var(--spacing-half);
		padding-left: var(--spacing);
		font-size: var(--small-font-size);
		border-radius: var(--roundedness);
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
	}
</style>
