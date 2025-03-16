<script lang="ts">
	import monoEmoji from './monoEmoji';

	let {
		icon: count
	}: {
		icon: number | string;
	} = $props();
</script>

<span class="count">
	<span class="icon">
		{typeof count === 'string' ? monoEmoji(count) : count}
	</span>
</span>

<style>
	.count {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		border-radius: 3em;
		padding: var(--spacing);
		background: var(--salient-color);
		color: var(--background-color);
		min-width: 1em;
		height: 1em;
		font-size: var(--small-font-size);
		align-self: start;
		font-family: 'Noto Emoji', 'Josefin Sans', sans-serif;
	}
</style>
