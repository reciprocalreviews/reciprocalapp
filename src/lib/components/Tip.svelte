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
		background: var(--salient-color-faded);
		padding: var(--spacing-half);
		border-radius: var(--roundedness);
		border-left: var(--thick-border-width) solid var(--salient-color);
	}

	.tip.border {
		border-top: var(--border-width) solid var(--border-color);
		border-bottom: var(--border-width) solid var(--border-color);
		padding-top: var(--spacing);
		padding-bottom: var(--spacing);
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
