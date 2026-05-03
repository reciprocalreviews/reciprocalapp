<script lang="ts">
	import { type SubmissionRow } from '$data/types';
	import { SubmissionLabel } from './Labels';
	import Link from './Link.svelte';

	export let submission: SubmissionRow | null;
</script>

{#if submission}
	<Link to="/venue/{submission.venue}/submission/{submission.id}" icon={SubmissionLabel}
		>{submission.title}</Link
	>
{/if}
