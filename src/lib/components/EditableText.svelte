<script lang="ts">
	import { tick } from 'svelte';
	import Button from './Button.svelte';
	import TextField from './TextField.svelte';
	import Dots from './Dots.svelte';

	type Props = {
		text: string;
		placeholder: string;
		empty: string;
		edit: (text: string) => Promise<string | undefined>;
	};

	let { text, placeholder, empty, edit }: Props = $props();

	// Whether the text is being edited.
	let editing = $state<boolean | undefined>(false);
	let error = $state<string | undefined>(undefined);
	let field = $state<HTMLInputElement | HTMLTextAreaElement | undefined>(undefined);
	let button = $state<HTMLButtonElement | undefined>(undefined);

	async function saveEdit(event: Event) {
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

<form>
	{#if editing}
		<TextField bind:text {placeholder} padded={false} bind:view={field} />
	{:else if text === ''}{empty}{:else}{text}{/if}
	<Button
		bind:view={button}
		type="submit"
		action={(event) => (editing ? saveEdit(event) : startEditing(event))}
		>{#if editing}✓{:else if editing === undefined}<Dots />{:else}✎{/if}</Button
	>
</form>

<style>
	form {
		display: flex;
		flex-direction: row;
		align-items: baseline;
		gap: var(--spacing);
	}
</style>
