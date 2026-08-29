<script lang="ts">
	import { type SubmissionRow } from '$data/types';
	import { SubmissionLabel } from './Labels';
	import Link from './Link.svelte';

	export let submission: SubmissionRow | null;
	/** The venue's web address, when the caller has it. A submission row carries only its
	 * venue's id, and the venue layout redirects an id to the address, so this changes
	 * which URL a reader sees rather than whether the link works. */
	export let venueSlug: string | null = null;
</script>

{#if submission}
	<Link
		to="/venue/{venueSlug ?? submission.venue}/submission/{submission.id}"
		icon={SubmissionLabel}>{submission.title}</Link
	>
{/if}
