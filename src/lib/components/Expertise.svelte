<script lang="ts">
	import Tag from './Tag.svelte';

	export let phrases: string[];
</script>

<div class="list">
	{#each phrases as expertise}<Tag>{expertise}</Tag>
	{/each}
</div>

<style>
	.list {
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		gap: var(--spacing);
		row-gap: var(--spacing);
		margin-block-start: 1em;
		margin-block-end: 1em;
	}
</style>
