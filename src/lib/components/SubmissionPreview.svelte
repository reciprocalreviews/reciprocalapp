<script lang="ts">
	import { type SubmissionRow } from '$data/types';
	import Link from './Link.svelte';

	export let submission: SubmissionRow;
</script>

<div class="submission">
	<Link to="/venue/{submission.venue}/submission/{submission.id}">{submission.title}</Link>
</div>

<style>
	.submission {
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
	}
</style>
