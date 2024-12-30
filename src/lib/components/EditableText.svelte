<script lang="ts">
	import { tick } from 'svelte';
	import Button from './Button.svelte';
	import TextField from './TextField.svelte';
	import Dots from './Dots.svelte';
	import Note from './Note.svelte';
	import { handle } from '../../routes/feedback.svelte';
	import { type ErrorID } from '$lib/data/CRUD';
	import { ConfirmLabel, DeleteLabel, EditLabel } from './Labels';

	type Props = {
		text: string;
		label?: string | undefined;
		placeholder: string;
		inline?: boolean;
		valid?: undefined | ((text: string) => boolean);
		edit: (text: string) => Promise<ErrorID | undefined>;
		note?: string;
	};

	let {
		text,
		label,
		placeholder,
		edit,
		valid = undefined,
		inline = true,
		note = undefined
	}: Props = $props();

	const original = text;

	// Whether the text is being edited.
	let editing = $state<boolean | undefined>(false);
	let field = $state<HTMLInputElement | HTMLTextAreaElement | undefined>(undefined);
	let button = $state<HTMLButtonElement | undefined>(undefined);

	let invalid = $derived(valid !== undefined && !valid(text));

	async function saveEdit(event?: Event) {
		if (invalid) {
			editing = false;
			text = original;
			return;
		}

		event?.preventDefault();

		await saveAndFocus();
	}

	async function startEditing(event?: Event) {
		editing = true;
		await tick();
		if (field) field.focus();
		event?.preventDefault();
	}

	async function saveAndFocus() {
		editing = undefined;
		if (await handle(edit(text))) {
			editing = false;
			if (button) button.focus();
		} else {
			editing = true;
		}
	}
</script>

<div class="editable" class:inline>
	<Button
		bind:view={button}
		tip={editing ? 'Save ' + (label ?? placeholder) : 'Edit ' + (label ?? placeholder)}
		type="submit"
		active={valid && editing ? valid(text) : undefined}
		action={(event) => (editing ? saveEdit(event) : startEditing(event))}
		>{#if editing}{invalid ? DeleteLabel : ConfirmLabel}{:else if editing === undefined}<Dots
			/>{:else}{EditLabel}{/if}</Button
	>
	<div class="box" class:inline class:editing>
		<TextField
			{label}
			{inline}
			{valid}
			bind:text
			{placeholder}
			padded={false}
			active={editing}
			bind:view={field}
			done={() => (editing ? saveAndFocus() : undefined)}
		/>
		{#if note}
			<Note>{note}</Note>
		{/if}
	</div>
</div>

<style>
	.editable {
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
		align-items: baseline;
	}

	.editable.inline {
		align-items: center;
	}

	.box {
		display: flex;
		flex-direction: column;
		justify-content: space-between;
		gap: var(--spacing);
		align-items: baseline;
		flex: 1;
		/* To align with the button*/
		padding-block-start: calc(var(--spacing) / 2);
	}

	.box.inline {
		align-items: end;
	}
</style>
