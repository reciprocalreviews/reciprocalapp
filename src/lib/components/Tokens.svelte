<script lang="ts">
	import type { CurrencyRow } from '$data/types';

	let { amount, currency }: { amount: number; currency?: CurrencyRow } = $props();
</script>

<span class="token"
	>★ {amount}
	{#if currency}<span class="currency">{currency.name}</span>
	{/if}
	token{#if amount !== 1}s{/if}</span
>

<style>
	.token {
		font-weight: 500;
		font-size: var(--small-font-size);
		padding: calc(var(--spacing) / 2);
		border-radius: var(--roundedness);
		background: var(--salient-color);
		color: var(--background-color);
		white-space: nowrap;
	}

	.currency {
		font-weight: 300;
	}
</style>
