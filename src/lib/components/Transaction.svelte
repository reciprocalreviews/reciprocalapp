<script lang="ts">
	import type Transaction from '$lib/types/Transaction';
	import ScholarLink from './ScholarLink.svelte';
	import Tag from './Tag.svelte';
	import Tokens from './Tokens.svelte';

	export let transaction: Transaction;
</script>

<div class="transaction">
	<Tag>{transaction.purpose}</Tag>
	<Tokens amount={transaction.amount} />
	<ScholarLink id={transaction.scholarID} />
</div>

<style>
	.transaction {
		display: flex;
		flex-direction: row;
		flex-wrap: nowrap;
		gap: var(--spacing);
		margin-block-start: var(--spacing);
		margin-block-end: var(--spacing);
		align-items: baseline;
	}
</style>
