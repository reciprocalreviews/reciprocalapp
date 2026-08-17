<script lang="ts">
	import { IdeaLabel } from '$lib/components/Labels';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import markdownToSegments from '$lib/data/markdownSegments';
	import updates from './updates.json';

	// Get the dated updates in reverse chronological order.
	const datedUpdates = updates
		.filter((update) => update.date !== null)
		.map((update) => ({
			...update,
			// Add a time zone to ensure consistent sorting regardless of the user's locale().
			date: update.date + 'T00:00:00'
		}))
		.toSorted((a, b) => {
			return new Date(b.date).getTime() - new Date(a.date).getTime();
		});
</script>

{#snippet note(text: string)}
	<!-- Convert markdown into Wordplay markup -->
	<li>
		{#each markdownToSegments(text) as segment}
			{#if typeof segment === 'string'}
				{segment}
			{:else if segment.type === 'issue'}
				<a href="https://github.com/reciprocalreviews/reciprocalapp/issues/{segment.text}"
					>#{segment.text}</a
				>
			{:else if segment.type === 'code'}
				<code>{segment.text}</code>
			{:else if segment.type === 'bold'}
				<strong>{segment.text}</strong>
			{:else if segment.type === 'italic'}
				<em>{segment.text}</em>
			{:else if segment.type === 'link'}
				<a href={segment.link}>{segment.text}</a>
			{/if}
		{/each}
	</li>
{/snippet}

<Page icon={IdeaLabel} title={(l) => l.page.updates.title} breadcrumbs={[]}>
	<Paragraph text={(l) => l.page.updates.paragraph.intro} />

	{#each datedUpdates as update}
		<Subheader
			icon="📅"
			text={new Date(update.date).toLocaleDateString(undefined, {
				year: 'numeric',
				month: 'long',
				day: 'numeric'
			})}
		/>

		{#if update.changes.added.length > 0}
			<h3 class="added">Added</h3>
			<ul>
				{#each update.changes.added as item}
					{@render note(item)}
				{/each}
			</ul>
		{/if}
		{#if update.changes.changed.length > 0}
			<h3 class="changed">Changed</h3>
			<ul>
				{#each update.changes.changed as item}
					{@render note(item)}
				{/each}
			</ul>
		{/if}
		{#if update.changes.fixed.length > 0}
			<h3 class="fixed">Fixed</h3>
			<ul>
				{#each update.changes.fixed as item}
					{@render note(item)}
				{/each}
			</ul>
		{/if}
		{#if update.changes.removed.length > 0}
			<h3 class="removed">Removed</h3>
			<ul>
				{#each update.changes.removed as item}
					{@render note(item)}
				{/each}
			</ul>
		{/if}
	{/each}
</Page>

<style>
	h3 {
		padding: var(--wordplay-spacing);
		border-radius: var(--wordplay-border-radius);
		color: var(--wordplay-background);
		display: inline-block;
		font-weight: bold;
	}

	h3.added {
		background: var(--wordplay-focus-color);
	}

	h3.changed {
		background: var(--wordplay-evaluation-color);
	}
	h3.removed {
		background: var(--wordplay-warning);
	}
	h3.fixed {
		background: var(--wordplay-error);
	}
</style>
