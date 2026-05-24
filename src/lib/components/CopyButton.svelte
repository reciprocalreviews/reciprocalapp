<script lang="ts">
	import Button from './Button.svelte';

	let { text, testid }: { text: string; testid?: string } = $props();

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
	strings={(l) => (copied ? l.component.copyButton.copied : l.component.copyButton.copy)}
	{testid}
	action={copy}
/>
