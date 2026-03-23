<script lang="ts">
	import { tick } from 'svelte';
	import Button from './Button.svelte';
	import TextField from './TextField.svelte';
	import { handle } from '../../routes/feedback.svelte';
	import type { Result } from '$lib/data/CRUD';
	import { type LocaleText, type TextFieldText } from '$lib/locales/Locale';
	import type Locale from '$lib/locales/Locale';

	type Props = {
		text: string;
		strings: (l: Locale) => TextFieldText;
		inline?: boolean;
		valid?: undefined | ((text: string) => undefined | ((l: LocaleText) => string));
		edit: (text: string) => Promise<Result>;
	};

	let { text, strings, edit, valid = undefined, inline = true }: Props = $props();

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
		strings={editing
			? invalid
				? (l) => l.component.text.cancel
				: (l) => l.component.text.save
			: (l) => l.component.text.edit}
		type="submit"
		active={valid !== undefined && editing ? valid(text) === undefined : undefined}
		action={(event) => (editing ? saveEdit(event) : startEditing(event))}
	></Button>
	<TextField
		{strings}
		{inline}
		{valid}
		bind:text
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
		align-items: baseline;
	}

	.editable.inline {
		align-items: stretch;
	}

	.editable :global(.field) {
		align-self: center;
	}
</style>
