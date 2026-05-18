<script lang="ts">
	import type { PreferenceLevelRow, VenueRow } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import { DeleteLabel } from '$lib/components/Labels';
	import TextField from '$lib/components/TextField.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { isntEmpty } from '$lib/validation';
	import { handle } from '$routes/feedback.svelte';

	let {
		venue,
		levels
	}: {
		venue: VenueRow;
		levels: PreferenceLevelRow[];
	} = $props();

	const db = getDB();

	let newLabel = $state('');

	let sorted = $derived([...levels].sort((a, b) => a.rank - b.rank));
</script>

{#if sorted.length === 0}
	<Feedback text={(l) => l.page.settings.feedback.noPreferenceLevels} />
{:else}
	<ol data-testid="preference-levels">
		{#each sorted as level, index (level.id)}
			<li>
				<EditableText
					testid="preference-level-{level.rank}"
					text={level.label}
					strings={(l) => l.page.settings.field.preferenceLevelLabel}
					valid={(text) =>
						isntEmpty(text)
							? undefined
							: (l) => l.page.settings.field.preferenceLevelLabel.invalid}
					edit={(text) => db().editPreferenceLevelLabel(level.id, text)}
				/>
				<Button
					active={index > 0}
					strings={(l) => l.page.settings.button.movePreferenceLevelUp}
					action={() =>
						handle(db().reorderPreferenceLevel(level, $state.snapshot(sorted), -1))}
				>↑</Button>
				<Button
					active={index < sorted.length - 1}
					strings={(l) => l.page.settings.button.movePreferenceLevelDown}
					action={() =>
						handle(db().reorderPreferenceLevel(level, $state.snapshot(sorted), 1))}
				>↓</Button>
				<Button
					strings={(l) => l.page.settings.button.deletePreferenceLevel}
					action={() => handle(db().deletePreferenceLevel(level.id))}
				>{DeleteLabel}</Button>
			</li>
		{/each}
	</ol>
{/if}

<Form>
	<TextField
		testid="new-preference-level"
		strings={(l) => l.page.settings.field.newPreferenceLevel}
		bind:text={newLabel}
		size={19}
		valid={(text) =>
			isntEmpty(text) ? undefined : (l) => l.page.settings.field.newPreferenceLevel.invalid}
	/>
	<Button
		testid="add-preference-level"
		strings={(l) => l.page.settings.button.addPreferenceLevel}
		active={isntEmpty(newLabel)}
		action={async () => {
			const result = await handle(db().createPreferenceLevel(venue.id, newLabel));
			if (typeof result !== 'boolean') newLabel = '';
		}}
	/>
</Form>
