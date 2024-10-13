<script lang="ts">
	import { tick } from 'svelte';
	import Button from './Button.svelte';
	import TextField from './TextField.svelte';
	import Dots from './Dots.svelte';
	import Note from './Note.svelte';
	import { addError } from '../../routes/errors.svelte';
	import { type ErrorID } from '$lib/data/Database';
	import { ConfirmLabel, DeleteLabel, EditLabel } from './Labels';

	type Props = {
		text: string;
		label?: string | undefined;
		placeholder: string;
		change: string;
		save: string;
		inline?: boolean;
		valid?: undefined | ((text: string) => boolean);
		edit: (text: string) => Promise<ErrorID | undefined>;
		note?: string;
	};

	let {
		text,
		label,
		placeholder,
		save,
		change,
		edit,
		valid = undefined,
		inline = true,
		note = undefined
	}: Props = $props();

	const original = text;

	// Whether the text is being edited.
	let editing = $state<boolean | undefined>(false);
	let error = $state<ErrorID | undefined>(undefined);
	let field = $state<HTMLInputElement | HTMLTextAreaElement | undefined>(undefined);
	let button = $state<HTMLButtonElement | undefined>(undefined);

	let invalid = $derived(valid !== undefined && !valid(text));

	async function saveEdit(event: Event) {
		if (invalid) {
			editing = false;
			text = original;
			return;
		}

		event.preventDefault();

		await saveAndFocus();
	}

	async function startEditing(event: Event) {
		editing = true;
		await tick();
		if (field) field.focus();
		event.preventDefault();
	}

	async function saveAndFocus() {
		editing = undefined;
		error = await edit(text);
		if (error) {
			editing = true;
			addError(error);
		} else {
			editing = false;
			if (button) button.focus();
		}
	}
</script>

<div class="editable">
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
		<Button
			bind:view={button}
			tip={editing ? save : change}
			type="submit"
			action={(event) => (editing ? saveEdit(event) : startEditing(event))}
			>{#if editing}{invalid ? DeleteLabel : ConfirmLabel}{:else if editing === undefined}<Dots
				/>{:else}{EditLabel}{/if}</Button
		>
	</div>
	{#if note}
		<Note>{note}</Note>
	{/if}
</div>

<style>
	.editable {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
	}

	.box {
		display: flex;
		flex-direction: row;
		justify-content: space-between;
		gap: var(--spacing);
	}

	.box.inline {
		align-items: center;
	}
</style>
