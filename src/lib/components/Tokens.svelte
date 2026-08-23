<script lang="ts">
	import type { CurrencyRow } from '$data/types';
	import { getLocaleContext } from '$routes/Contexts';
	import { TokenLabel } from './Labels';

	let {
		amount,
		currency,
		debit = false
	}: { amount: number; debit?: boolean; currency?: CurrencyRow } = $props();

	let locale = getLocaleContext();
</script>

<span class="token" class:debit
	><span class="star">{TokenLabel}</span>
	{amount}
	{#if currency}<span class="currency">{currency.name}</span>
	{/if}
	{#if amount === 1}{locale().widget.tokens.single}{:else}{locale().widget.tokens.plural}{/if}</span
>

<!-- No scoped styles: `.token` and friends live in the global block in src/app.html.
     Svelte's scoping never reaches `{@html}` content, and the same chip is emitted as an
     HTML string by tokenChip() so it can appear inside a localized sentence. Two copies of
     these rules would drift; one global copy serves both. -->
