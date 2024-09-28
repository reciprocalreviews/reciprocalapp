<script lang="ts">
	import { tick } from 'svelte';
	import Button from './Button.svelte';
	import TextField from './TextField.svelte';
	import Dots from './Dots.svelte';
	import Note from './Note.svelte';

	type Props = {
		text: string;
		placeholder: string;
		empty: string;
		inline?: boolean;
		valid?: undefined | ((text: string) => boolean);
		edit: (text: string) => Promise<string | undefined>;
		note?: string;
	};

	let {
		text,
		placeholder,
		empty,
		edit,
		valid = undefined,
		inline = true,
		note = undefined
	}: Props = $props();

	const original = text;

	// Whether the text is being edited.
	let editing = $state<boolean | undefined>(false);
	let error = $state<string | undefined>(undefined);
	let field = $state<HTMLInputElement | HTMLTextAreaElement | undefined>(undefined);
	let button = $state<HTMLButtonElement | undefined>(undefined);

	let invalid = $derived(valid !== undefined && !valid(text));

	async function saveEdit(event: Event) {
		if (invalid) {
			editing = false;
			text = original;
			return;
		}

		editing = undefined;
		event.preventDefault();
		error = await edit(text);
		if (error) {
			editing = true;
		} else {
			editing = false;
			if (button) button.focus();
		}
	}

	async function startEditing(event: Event) {
		editing = true;
		await tick();
		if (field) field.focus();
		event.preventDefault();
	}
</script>

<div class="editable">
	<form class:inline>
		{#if editing}
			<TextField {inline} {valid} bind:text {placeholder} padded={false} bind:view={field} />
		{:else if text === ''}{empty}{:else}{text}{/if}
		<Button
			bind:view={button}
			type="submit"
			action={(event) => (editing ? saveEdit(event) : startEditing(event))}
			>{#if editing}{invalid ? '𐄂' : '✓'}{:else if editing === undefined}<Dots
				/>{:else}✎{/if}</Button
		>
	</form>
	<div class="note">
		{#if note}
			<Note>{note}</Note>
		{/if}
	</div>
</div>

<style>
	.editable {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
	}

	form {
		display: flex;
		flex-direction: row;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--spacing);
	}

	form.inline {
		align-items: center;
	}

	.note {
		margin-inline-start: var(--spacing);
	}
</style>
