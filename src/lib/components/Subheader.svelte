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
	h2 {
		display: flex;
		gap: 0.25rem;
		align-items: baseline;
	}

	span {
		font-family: 'Noto Emoji', 'Josefin Sans', sans-serif;
		color: var(--border-color);
	}
</style>
