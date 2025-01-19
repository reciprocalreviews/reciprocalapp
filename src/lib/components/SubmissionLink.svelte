<script lang="ts">
	import { type SubmissionRow } from '$data/types';
	import Link from './Link.svelte';

	export let submission: SubmissionRow;
</script>

<div class="submission">
	<span class="icon">💡</span>
	<Link to="/venue/{submission.venue}/submission/{submission.id}">{submission.title}</Link>
</div>

<style>
	.submission {
		display: flex;
		flex-direction: row;
		flex-wrap: nowrap;
		gap: var(--spacing);
	}
</style>
