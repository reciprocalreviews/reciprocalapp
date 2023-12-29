<script lang="ts">
	import Note from './Note.svelte';

	export let editor: boolean;
</script>

{#if editor}
	<div class="editors">
		<Note>Editors Only</Note>
		<slot />
	</div>
{/if}

<style>
	.editors {
		padding: var(--spacing);
		border-radius: var(--roundedness);
		border: 1px dotted var(--salient-color);
		margin-top: 1em;
		margin-bottom: 1em;
		background: var(--alternating-color);
	}
</style>
