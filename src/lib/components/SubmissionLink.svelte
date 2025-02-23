<script lang="ts">
	import { type SubmissionRow } from '$data/types';
	import Link from './Link.svelte';

	export let submission: SubmissionRow;
</script>

<div class="submission">
	<span class="icon">💡</span>
	<Link to="/submission/{submission.id}">{submission.title}</Link>
</div>

<style>
	.submission {
		display: flex;
		flex-direction: row;
		flex-wrap: nowrap;
		gap: 0.25em;
	}
</style>
