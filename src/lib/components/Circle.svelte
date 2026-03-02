<script lang="ts">
	import monoEmoji from './monoEmoji';

	let {
		icon: count
	}: {
		icon: number | string;
	} = $props();
</script>

<span class="count">
	<span class="icon {typeof count === 'string' && /\p{Emoji}/gu.test(count) ? 'emoji' : ''}">
		{typeof count === 'string' ? monoEmoji(count) : count}
	</span>
</span>

<style>
	.count {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		border-radius: 50%;
		padding: calc(var(--spacing) * 0.8);
		background: var(--salient-color);
		color: var(--background-color);
		min-width: 0.5em;
		height: 0.5em;
		font-size: var(--small-font-size);
		align-self: start;
		font-family: 'Josefin Sans', sans-serif;
	}

	.emoji {
		font-family: 'Noto Emoji', 'Josefin Sans', sans-serif;
	}
</style>
