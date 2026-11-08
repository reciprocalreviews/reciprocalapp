<script lang="ts">
	import type { Snippet } from 'svelte';
	import monoEmoij from './monoEmoji';

	interface Props {
		border?: boolean;
		children: Snippet;
	}

	let { border = true, children }: Props = $props();
</script>

<div class="tip" class:border>
	<div class="bulb">{monoEmoij('💡')}</div>
	<div class="content">{@render children()}</div>
</div>

<style>
	.tip {
		display: flex;
		flex-direction: row;
		flex-wrap: nowrap;
		gap: var(--spacing-half);
		align-items: first baseline;
		font-size: var(--small-font-size);
	}

	/* No box. A boxed tip was the default Feedback with a bulb in it, so help read as a
	   notice and notices read as help; alerts now own the faded box, and help is quiet
	   type. `border` survives as a rule in the margin, for the few tips that sit loose in
	   a page rather than under the field they explain. */
	.tip.border {
		padding-inline-start: var(--spacing-half);
		border-left: var(--border-width) solid var(--border-color);
		color: var(--text-color);
	}

	.bulb {
		font-size: 100%;
		animation: slideUp 0.5s;
	}

	.content {
		font-style: italic;
	}

	@keyframes slideUp {
		from {
			opacity: 0;
			transform: translateY(1em);
		}
		to {
			opacity: 1;
			transform: translateY(0);
		}
	}
</style>
