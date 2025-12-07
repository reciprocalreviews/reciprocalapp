<script lang="ts">
	import { tick } from 'svelte';
	import Button from './Button.svelte';
	import TextField from './TextField.svelte';
	import Dots from './Dots.svelte';
	import { handle } from '../../routes/feedback.svelte';
	import { ConfirmLabel, DeleteLabel, EditLabel } from './Labels';
	import type { Result } from '$lib/data/CRUD';

	type Props = {
		text: string;
		label?: string | undefined;
		placeholder: string;
		inline?: boolean;
		valid?: undefined | ((text: string) => string | undefined);
		edit: (text: string) => Promise<Result>;
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

	// svelte-ignore state_referenced_locally
	const original = $state(text);

	// Whether the text is being edited.
	let editing = $state<boolean | undefined>(false);
	let field = $state<HTMLInputElement | HTMLTextAreaElement | undefined>(undefined);
	let button = $state<HTMLButtonElement | undefined>(undefined);

	let invalid = $derived(valid !== undefined && valid(text) !== undefined);

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
		active={valid !== undefined && editing ? valid(text) === undefined : undefined}
		action={(event) => (editing ? saveEdit(event) : startEditing(event))}
		>{#if editing}{invalid ? DeleteLabel : ConfirmLabel}{:else if editing === undefined}<Dots
			/>{:else}{EditLabel}{/if}</Button
	>
	<TextField
		{label}
		{note}
		{inline}
		{valid}
		bind:text
		{placeholder}
		active={editing}
		bind:view={field}
		done={() => (editing ? saveAndFocus() : undefined)}
	/>
</div>

<style>
	.editable {
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
		align-items: normal;
	}

	.editable.inline {
		align-items: normal;
	}
</style>
