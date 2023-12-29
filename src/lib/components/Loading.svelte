<script lang="ts">
	import { onMount } from 'svelte';
	import Feedback from './Feedback.svelte';

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

<Feedback>Loading {'.'.repeat(dots + 1)}</Feedback>
