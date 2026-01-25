<script lang="ts">
	import type { Snippet } from 'svelte';

	interface Props {
		icon: string;
		id?: string;
		children: Snippet;
	}

	let { icon, id, children }: Props = $props();
</script>

<h2 {id}>
	<span>{icon}</span>
	{@render children()}
</h2>

<style>
	span {
		font-family: 'Noto Emoji', 'Josefin Sans', sans-serif;
		font-size: 80%;
		color: var(--inactive-color);
	}
</style>
