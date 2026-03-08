<script lang="ts">
	import updates from './updates.json';
	import Page from '$lib/components/Page.svelte';
	import { IdeaLabel } from '$lib/components/Labels';
	import Subheader from '$lib/components/Subheader.svelte';

	// Get the dated updates in reverse chronological order.
	const datedUpdates = updates
		.filter((update) => update.date !== null)
		.map((update) => ({
			...update,
			// Add a time zone to ensure consistent sorting regardless of the user's locale.
			date: update.date + 'T00:00:00'
		}))
		.toSorted((a, b) => {
			return new Date(b.date).getTime() - new Date(a.date).getTime();
		});

	function markdownToSegments(text: string) {
		const segments: (
			| string
			| { type: 'issue' | 'code' | 'bold' | 'italic' | 'link'; text: string }
		)[] = [];
		let currentIndex = 0;
		const regex = /#([0-9]+)|`([^`]+)`|\*\*([^*]+)\*\*|\*([^*]+)\*|\[([^\]]+)\]\(([^)]+)\)/g;
		let match;

		while ((match = regex.exec(text)) !== null) {
			if (match.index > currentIndex) {
				segments.push(text.substring(currentIndex, match.index));
			}
			if (match[1]) {
				segments.push({ type: 'issue', text: match[1] });
			} else if (match[2]) {
				segments.push({ type: 'code', text: match[2] });
			} else if (match[3]) {
				segments.push({ type: 'bold', text: match[3] });
			} else if (match[4]) {
				segments.push({ type: 'italic', text: match[4] });
			} else if (match[5]) {
				segments.push({ type: 'link', text: match[5] });
			}
			currentIndex = regex.lastIndex;
		}

		if (currentIndex < text.length) {
			segments.push(text.substring(currentIndex));
		}

		return segments;
	}
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
				<a href={segment.text}>{segment.text}</a>
			{/if}
		{/each}
	</li>
{/snippet}

<Page icon={IdeaLabel} title="Updates" breadcrumbs={[['/', 'Home']]}>
	<p>
		Here are the updates to Reciprocal Reviews. Have an <a
			href="https://github.com/reciprocalreviews/reciprocalapp/issues/new?template=1-defect.yml"
			>defect</a
		>
		to report or
		<a
			href="https://github.com/reciprocalreviews/reciprocalapp/issues/new?template=2-improvement.yml"
			>improvement</a
		> to suggest?
	</p>

	{#each datedUpdates as update}
		<Subheader icon="📅">
			{new Date(update.date).toLocaleDateString(undefined, {
				year: 'numeric',
				month: 'long',
				day: 'numeric'
			})}
		</Subheader>

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
