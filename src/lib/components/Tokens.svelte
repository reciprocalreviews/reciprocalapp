<script lang="ts">
	import type { CurrencyRow } from '$data/types';
	import { TokenLabel } from './Labels';

	let { amount, currency }: { amount: number; currency?: CurrencyRow } = $props();
</script>

<span class="token"
	><span class="star">{TokenLabel}</span>
	{amount}
	{#if currency}<span class="currency">{currency.name}</span>
	{/if}
	token{#if amount !== 1}s{/if}</span
>

<style>
	.token {
		font-weight: 500;
		font-size: var(--small-font-size);
		padding: var(--spacing-half);
		border-radius: var(--roundedness);
		background-color: var(--salient-color-faded);
		box-decoration-break: clone;
	}

	.star {
		color: var(--salient-color);
	}

	.currency {
		font-weight: 300;
	}
</style>
