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
		gap: var(--spacing);
		align-items: start;
		font-size: var(--small-font-size);
		border-radius: var(--roundedness);
	}

	.bulb {
		font-size: 125%;
		animation: slideUp 0.5s;
	}

	.content {
		border-left: solid var(--thick-border-width) var(--border-color);
		padding-left: var(--spacing);
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
