<script lang="ts">
	import type { Snippet } from 'svelte';
	import { TokenLabel } from './Labels';
	import Link from './Link.svelte';

	interface Props {
		currency: { id: string; name: string };
		children?: Snippet;
		transactions?: boolean;
	}

	let { currency, children, transactions = false }: Props = $props();
</script>

<Link background to="/currency/{currency.id}{transactions ? '/transactions' : ''}"
	>{#if children}{@render children()}{:else}{TokenLabel} {currency.name}{/if}</Link
>
