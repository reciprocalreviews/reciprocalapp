<script lang="ts">
	import { type SubmissionRow } from '$data/types';
	import { SubmissionLabel } from './Labels';
	import Link from './Link.svelte';

	export let submission: SubmissionRow;
</script>

<Link to="/venue/{submission.venue}/submission/{submission.id}" icon={SubmissionLabel}
	>{submission.title}</Link
>
