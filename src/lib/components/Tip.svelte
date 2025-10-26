<script lang="ts">
	import monoEmoij from './monoEmoji';

	let { children } = $props();
</script>

<div class="tip">
	<div class="bulb">{monoEmoij('💡')}</div>
	<div class="content">{@render children()}</div>
</div>

<style>
	.tip {
		display: flex;
		flex-direction: row;
		flex-wrap: nowrap;
		gap: calc(var(--spacing) / 2);
		align-items: start;
		font-size: var(--small-font-size);
		border-top: var(--border-width) solid var(--border-color);
		border-bottom: var(--border-width) solid var(--border-color);
		padding-top: var(--spacing);
		padding-bottom: var(--spacing);
	}

	.bulb {
		font-size: 125%;
		animation: slideUp 0.5s;
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
