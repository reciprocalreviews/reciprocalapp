<script lang="ts">
	import type { Snippet } from 'svelte';
	import { TokenLabel } from './Labels';
	import Link from './Link.svelte';

	interface Props {
		currency: { id: string; name: string };
		children?: Snippet;
	}

	let { currency, children }: Props = $props();
</script>

<Link background to="/currency/{currency.id}"
	>{#if children}{@render children()}{:else}{TokenLabel} {currency.name}{/if}</Link
>
