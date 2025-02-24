<script lang="ts">
	import { type Snippet, tick } from 'svelte';
	import { clickOutside } from './clickOutside';
	import Button from './Button.svelte';
	import monoEmoij from './monoEmoji';

	interface Props {
		show?: boolean;
		closeable?: boolean;
		children: Snippet;
	}

	let { show = $bindable(false), closeable = true, children }: Props = $props();

	let view: HTMLDialogElement | undefined = $state(undefined);

	/** Show and focus dialog when shown, hide when not. */
	$effect(() => {
		if (view) {
			if (show) {
				view.showModal();
				tick().then(() => (view ? view.focus() : undefined));
			} else {
				view.close();
			}
		}
	});
</script>

<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<dialog
	bind:this={view}
	use:clickOutside={() => (show = false)}
	tabindex="-1"
	onkeydown={closeable
		? (event) => (event.key === 'Escape' ? (show = false) : undefined)
		: undefined}
>
	<div class="container">
		{#if closeable}
			<div class="close">
				<Button background={false} tip="Close this dialog" action={() => (show = false)}
					>{monoEmoij('✖')}</Button
				>
			</div>
		{/if}

		<div class="content">
			{@render children()}
		</div>
	</div>
</dialog>

<style>
	dialog {
		position: relative;
		border-radius: var(--roundedness);
		padding: 0;
		margin-left: auto;
		margin-right: auto;
		max-width: 95vw;
		height: max-content;
		background-color: var(--background-color);
		color: var(--foreground);
		border: var(--border-width) solid var(--border-color);
	}

	dialog::backdrop {
		transition: backdrop-filter;
		backdrop-filter: blur(2px);
	}

	.container {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
		padding: 1em;
		min-width: 50vw;
	}

	.close {
		position: sticky;
		top: 0;
		width: 100%;
		text-align: right;
	}

	.content {
		min-height: 100%;
		padding: 1em;
		padding-top: 0;
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
	}
</style>
