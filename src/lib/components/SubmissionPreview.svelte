<script lang="ts">
	import type Submission from '$lib/types/Submission';
	import Link from './Link.svelte';

	export let submission: Submission;
</script>

<div class="submission">
	<Link to="/submission/{submission.id}">{submission.title}</Link>
</div>

<style>
	.submission {
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
	}
</style>
