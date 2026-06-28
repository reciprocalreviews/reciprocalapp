<script lang="ts">
	import type { ScholarID, SubmissionRow, ThanksRow } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import { ThanksLabel } from '$lib/components/Labels';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Row from '$lib/components/Row.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { handle } from '$routes/feedback.svelte';

	/** Author thank-you notes to reviewers (#22). This component renders three
	 * audience-specific views off the same RLS-filtered `thanks` list:
	 *  - author (on a done submission): compose / status of their own note;
	 *  - vetter (venue admin / editor): approve or decline pending notes;
	 *  - recipient reviewer: read approved notes.
	 * It owns its own local form state so realtime refetches of `thanks` don't
	 * clobber in-progress edits. */
	let {
		submission,
		thanks,
		scholarID,
		isAuthor,
		isAssigned,
		isVetter,
		done
	}: {
		submission: SubmissionRow;
		thanks: ThanksRow[] | null;
		scholarID: ScholarID;
		isAuthor: boolean;
		isAssigned: boolean;
		isVetter: boolean;
		done: boolean;
	} = $props();

	const db = getDB();

	/** This author's own note for this submission, if any. */
	const myThanks = $derived(thanks?.find((t) => t.author === scholarID) ?? null);
	/** Proposed notes awaiting a vetter's decision. */
	const proposedThanks = $derived(thanks?.filter((t) => t.status === 'proposed') ?? []);
	/** Approved notes a recipient reviewer may read. */
	const receivedThanks = $derived(thanks?.filter((t) => t.status === 'approved') ?? []);
	/** Whether the author may (re)write a note: none yet, or a declined one. */
	const canWrite = $derived(myThanks === null || myThanks.status === 'declined');

	let message = $state('');
	let decliningID = $state<string | null>(null);
	let declineReason = $state('');
</script>

<!-- Author view: once a submission is done, its authors may send one note of
     thanks to everyone who reviewed it. Notes are vetted by an editor unless the
     venue disables vetting; reviewers stay anonymous to the author and delivery
     happens server-side. -->
{#if done && isAuthor}
	<Subheader icon={ThanksLabel} text={(l) => l.page.submission.thanks.header}></Subheader>
	{#if myThanks && myThanks.status === 'proposed'}
		<Feedback text={(l) => l.page.submission.thanks.pending} />
		<blockquote class="thanks-note">{myThanks.message}</blockquote>
	{:else if myThanks && myThanks.status === 'approved'}
		<Feedback text={(l) => l.page.submission.thanks.delivered} />
		<blockquote class="thanks-note">{myThanks.message}</blockquote>
	{/if}
	{#if canWrite}
		{#if myThanks && myThanks.status === 'declined'}
			<Feedback error text={(l) => l.page.submission.thanks.declinedReason} />
			{#if myThanks.decline_reason}
				<blockquote class="thanks-note">{myThanks.decline_reason}</blockquote>
			{/if}
		{/if}
		<Form>
			<Paragraph text={(l) => l.page.submission.thanks.intro} />
			<TextField
				bind:text={message}
				strings={(l) => l.page.submission.thanks.field.message}
				testid="thanks-message"
				stretch
				valid={(t) =>
					t.trim().length === 0 || t.length > 1000
						? (l) => l.page.submission.thanks.field.message.invalid
						: undefined}
			></TextField>
			<Button
				testid="thanks-send"
				strings={(l) => l.page.submission.thanks.button.send}
				active={message.trim().length > 0 && message.length <= 1000}
				action={async () => {
					await handle(db().proposeThanks(submission.id, message));
					message = '';
				}}
			/>
		</Form>
	{/if}
{/if}

<!-- Vetter view: venue admins / editors approve or decline pending notes. -->
{#if isVetter && proposedThanks.length > 0}
	<Subheader icon={ThanksLabel} text={(l) => l.page.submission.thanks.header}></Subheader>
	<Paragraph text={(l) => l.page.submission.thanks.review} />
	{#each proposedThanks as note (note.id)}
		<blockquote class="thanks-note">{note.message}</blockquote>
		<Row>
			<Button
				testid="thanks-approve"
				strings={(l) => l.page.submission.thanks.button.approve}
				action={() => handle(db().approveThanks(note.id))}
			/>
			<Button
				testid="thanks-decline"
				strings={(l) => l.page.submission.thanks.button.declineInitiate}
				active={decliningID !== note.id}
				action={() => {
					decliningID = note.id;
					declineReason = '';
					return undefined;
				}}
			/>
		</Row>
		{#if decliningID === note.id}
			<Form>
				<Paragraph text={(l) => l.page.submission.thanks.declineReasonPrompt} />
				<TextField
					bind:text={declineReason}
					strings={(l) => l.page.submission.thanks.field.declineReason}
					testid="thanks-decline-reason"
					stretch
				></TextField>
				<Button
					testid="thanks-decline-confirm"
					strings={(l) => l.page.submission.thanks.button.declineConfirm}
					active={declineReason.trim().length > 0}
					action={async () => {
						await handle(db().declineThanks(note.id, declineReason));
						decliningID = null;
						declineReason = '';
					}}
				/>
			</Form>
		{/if}
	{/each}
{/if}

<!-- Recipient view: reviewers read approved notes of thanks. -->
{#if isAssigned && !isAuthor && receivedThanks.length > 0}
	<Subheader icon={ThanksLabel} text={(l) => l.page.submission.thanks.received}></Subheader>
	{#each receivedThanks as note (note.id)}
		<blockquote class="thanks-note">{note.message}</blockquote>
	{/each}
{/if}

<style>
	.thanks-note {
		margin-block: var(--spacing-half);
		padding-inline-start: var(--spacing);
		border-inline-start: 3px solid var(--salient-color);
		font-style: italic;
		white-space: pre-wrap;
	}
</style>
