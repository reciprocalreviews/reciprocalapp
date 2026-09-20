<script lang="ts">
	import { type SubmissionRow } from '$data/types';
	import { SubmissionLabel } from './Labels';
	import Link from './Link.svelte';

	/** Only the three fields the link needs, so a caller may pass a projected row —
	 * scholar_tasks returns flat columns rather than an embedded submission. Every
	 * caller passing a whole SubmissionRow still satisfies this. */
	export let submission: Pick<SubmissionRow, 'id' | 'title' | 'venue'> | null;
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
