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
		testid?: string;
	};

	let {
		text: propText,
		strings,
		edit,
		valid = undefined,
		inline = true,
		testid = undefined
	}: Props = $props();

	/** Reading the text, editing it, or waiting on the write that saves it. `saving` is a
	 * state of its own rather than an absence of editing, because it has to be shown: a
	 * save on a slow connection is a second of silence otherwise. */
	let mode = $state<'view' | 'editing' | 'saving'>('view');
	let field = $state<HTMLInputElement | HTMLTextAreaElement | undefined>(undefined);
	let button = $state<HTMLButtonElement | undefined>(undefined);
	let wrapper = $state<HTMLDivElement | undefined>(undefined);

	// Local working copy so that a prop change mid-edit (e.g. a realtime
	// invalidateAll() triggered by another field's save) doesn't clobber the
	// user's in-progress input.
	// svelte-ignore state_referenced_locally
	let text = $state(propText);

	/** The prop as of the last time it was taken. Plain `let`, not `$state`, so the effect
	 * below can write it without re-triggering itself. */
	// svelte-ignore state_referenced_locally
	let lastProp = propText;

	/** Take the prop only when it genuinely changes, and only while nothing is being
	 * edited or saved — an update that lands mid-edit must not clobber what's being
	 * typed, and one that lands mid-save is picked up by `save()` instead. */
	$effect(() => {
		if (propText !== lastProp) {
			lastProp = propText;
			if (mode === 'view') text = propText;
		}
	});

	let invalid = $derived(valid !== undefined && valid(text) !== undefined);

	function toggle(event?: Event) {
		if (mode === 'view') return startEditing(event);
		if (mode === 'editing') return finishEditing(event);
		// A save is already in flight; the click that started it must not start another.
		return undefined;
	}

	async function startEditing(event?: Event) {
		mode = 'editing';
		await tick();
		if (field) field.focus();
		event?.preventDefault();
	}

	/** Leaving the field either saves it or, when what's there can't be saved, discards it
	 * — the same two outcomes the toggle offers as Save and Cancel. */
	async function finishEditing(event?: Event) {
		event?.preventDefault();
		if (invalid) cancel();
		else await save();
	}

	function cancel() {
		// Revert to the freshest known value rather than to whatever the text was when
		// editing began, which may predate an update that arrived while it was open.
		text = propText;
		lastProp = propText;
		mode = 'view';
	}

	async function save() {
		mode = 'saving';
		if (await handle(edit(text))) {
			// handle() waits for the invalidation, so the page data is current by the time
			// this resolves: take the value back from the prop, which is what was actually
			// kept. Usually that's the text just typed. Sometimes it isn't — VerifyEmail
			// leaves the stored address alone until the new one is verified — and the
			// field should show what's true, not what was asked for.
			text = propText;
			lastProp = propText;
			mode = 'view';
			await tick();
			if (button) button.focus();
		} else {
			// handle() has already raised the error banner. Put the field back the way the
			// user left it so the text they wrote is still there to fix.
			mode = 'editing';
			await tick();
			if (field) field.focus();
		}
	}

	/** Blurring the field saves it, except when focus went to the toggle button: that
	 * click is about to decide for itself, and saving first would close the field out
	 * from under it — which is how clicking Cancel used to save and then reopen. */
	function blurred(event?: FocusEvent) {
		if (mode !== 'editing') return;
		const to = event?.relatedTarget;
		if (to instanceof Node && wrapper?.contains(to)) return;
		finishEditing();
	}
</script>

<div class="editable" class:inline bind:this={wrapper}>
	<Button
		bind:view={button}
		strings={mode === 'saving'
			? (l) => l.component.text.saving
			: mode === 'editing'
				? invalid
					? (l) => l.component.text.cancel
					: (l) => l.component.text.save
				: (l) => l.component.text.edit}
		type="submit"
		active={mode !== 'saving'}
		testid={testid ? `${testid}-toggle` : undefined}
		action={toggle}
	></Button>
	<TextField
		{strings}
		{inline}
		{valid}
		bind:text
		active={mode === 'editing'}
		bind:view={field}
		done={blurred}
		{testid}
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
