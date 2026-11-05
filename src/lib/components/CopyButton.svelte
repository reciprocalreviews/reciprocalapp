<script lang="ts">
	import type { ButtonText } from '#lib/locales/Locale.js';
	import type LocaleText from '#lib/locales/Locale.js';
	import Button from './Button.svelte';

	let {
		text,
		testid,
		strings
	}: {
		text: string;
		testid?: string;
		/** What the button says before it is pressed, when "Copy" alone wouldn't say what
		 * gets copied. Afterwards it always says it copied. */
		strings?: (l: LocaleText) => ButtonText;
	} = $props();

	let copied = $state(false);
	let timer: ReturnType<typeof setTimeout> | undefined;

	async function copy() {
		await navigator.clipboard.writeText(text);
		copied = true;
		if (timer) clearTimeout(timer);
		timer = setTimeout(() => {
			copied = false;
		}, 2000);
	}
</script>

<Button
	strings={(l) =>
		copied ? l.component.copyButton.copied : (strings?.(l) ?? l.component.copyButton.copy)}
	{testid}
	action={copy}
/>
