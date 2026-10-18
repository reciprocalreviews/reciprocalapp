<script lang="ts">
	import type { DeclineReasonRow, VenueRow } from '$data/types';
	import Button from '#lib/components/Button.svelte';
	import EditableText from '#lib/components/EditableText.svelte';
	import Feedback from '#lib/components/Feedback.svelte';
	import Form from '#lib/components/Form.svelte';
	import { DeleteLabel } from '#lib/components/Labels.js';
	import TextField from '#lib/components/TextField.svelte';
	import { getDB } from '#lib/data/CRUD.js';
	import { handle } from '$routes/feedback.svelte';

	let {
		venue,
		reasons
	}: {
		venue: VenueRow;
		reasons: DeclineReasonRow[];
	} = $props();

	const db = getDB();

	let newText = $state('');

	let sorted = $derived([...reasons].sort((a, b) => a.rank - b.rank));

	/** The database's rule, decline_reasons_text_check. */
	function validReason(text: string) {
		const length = text.trim().length;
		return length > 0 && length <= 1000;
	}
</script>

{#if sorted.length === 0}
	<Feedback text={(l) => l.page.settings.feedback.noDeclineReasons} />
{:else}
	<ol data-testid="decline-reasons">
		{#each sorted as reason, index (reason.id)}
			<li data-testid="decline-reason-{index}">
				<EditableText
					testid="decline-reason-text-{index}"
					text={reason.text}
					inline={false}
					strings={(l) => l.page.settings.field.declineReasonText}
					valid={(text) =>
						validReason(text) ? undefined : (l) => l.page.settings.field.declineReasonText.invalid}
					edit={(text) => db().editDeclineReasonText(reason.id, text)}
				/>
				<div class="buttons">
					<Button
						testid="decline-reason-up-{index}"
						active={index > 0}
						strings={(l) => l.page.settings.button.moveDeclineReasonUp}
						action={() => handle(db().reorderDeclineReason(reason, $state.snapshot(sorted), -1))}
						>↑</Button
					>
					<Button
						testid="decline-reason-down-{index}"
						active={index < sorted.length - 1}
						strings={(l) => l.page.settings.button.moveDeclineReasonDown}
						action={() => handle(db().reorderDeclineReason(reason, $state.snapshot(sorted), 1))}
						>↓</Button
					>
					<Button
						testid="decline-reason-delete-{index}"
						strings={(l) => l.page.settings.button.deleteDeclineReason}
						action={() => handle(db().deleteDeclineReason(reason.id))}>{DeleteLabel}</Button
					>
				</div>
			</li>
		{/each}
	</ol>
{/if}

<Form>
	<!-- Forms shrink a field to its content; a sentence needs the width. -->
	<div class="new-reason">
		<TextField
			testid="new-decline-reason"
			strings={(l) => l.page.settings.field.newDeclineReason}
			bind:text={newText}
			inline={false}
			stretch
			valid={(text) =>
				validReason(text) ? undefined : (l) => l.page.settings.field.newDeclineReason.invalid}
		/>
	</div>
	<Button
		testid="add-decline-reason"
		strings={(l) => l.page.settings.button.addDeclineReason}
		active={validReason(newText)}
		action={async () => {
			// Cleared before the await and restored on failure, for the reason
			// PreferenceLevels.svelte gives: handle() ends in invalidateAll().
			const text = newText;
			newText = '';
			const result = await handle(db().createDeclineReason(venue.id, text));
			if (typeof result === 'boolean') newText = text;
		}}
	/>
</Form>

<style>
	ol {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
	}

	li {
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		align-items: baseline;
		gap: var(--spacing);
	}

	li > :global(:first-child) {
		flex: 1 1 20em;
		min-width: 0;
	}

	.new-reason {
		width: 100%;
	}

	.buttons {
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
	}
</style>
