<script lang="ts">
	import { onMount } from 'svelte';

	let dots = 0;

	onMount(() => {
		let interval = setInterval(() => {
			dots = (dots + 1) % 5;
		}, 250);

		return () => {
			clearInterval(interval);
		};
	});
</script>

<span>{'.'.repeat(dots + 1)}</span>
