<script lang="ts">
	import type { ScholarMatch } from '$lib/data/SupabaseCRUD.svelte';
	import Button from './Button.svelte';
	import Feedback from './Feedback.svelte';
	import Loading from './Loading.svelte';
	import ScholarLink from './ScholarLink.svelte';
	import type { ScholarSearch } from './ScholarSearch.svelte';

	let {
		search,
		choose,
		/** Whether to show the resolved scholar's name. Off where the caller renders
		 * its own list of who has been added, and the name would only repeat it. */
		showResolved = true,
		/** Rendered when there is nothing to say: no resolution, no search. */
		placeholder = undefined,
		foundTestid = undefined,
		matchTestid = undefined,
		noMatchesTestid = undefined
	}: {
		search: ScholarSearch;
		/** What choosing a match means. The new-submission form fills the row's
		 * ORCID; ScholarField replaces its text with it. */
		choose: (match: ScholarMatch) => void;
		showResolved?: boolean;
		placeholder?: string;
		foundTestid?: string;
		/** Prefix; each match gets `-{index}` appended. */
		matchTestid?: string;
		noMatchesTestid?: string;
	} = $props();
</script>

{#if search.state.status === 'loading'}
	<Loading />
{:else if search.state.status === 'found' && showResolved}
	<span data-testid={foundTestid}><ScholarLink id={search.state.id} /></span>
{:else if search.search.status === 'searching'}
	<Loading />
{:else if search.search.status === 'done'}
	{@const matches = search.search.matches}
	{#if matches.length > 0}
		<!-- Typed a name rather than an ORCID: offer the matches, and let a click
		     fill in the identifier the form actually needs. -->
		<div class="matches">
			{#each matches as match, index}
				<Button
					small
					strings={(l) => ({
						// The name goes in the TIP as well as the label, because the tip is
						// the button's aria-label: a column of buttons all announcing
						// "Choose this scholar" is unusable by voice or screen reader.
						tip: l.widget.scholarSearch.choose.tip.replace('{name}', match.name ?? ''),
						label: match.name ?? ''
					})}
					testid={matchTestid ? `${matchTestid}-${index}` : undefined}
					action={() => choose(match)}>{match.name}</Button
				>
			{/each}
		</div>
	{:else}
		<!-- Searched and found nobody. Distinct from the placeholder below, which
		     only means nothing has been typed yet. -->
		<Feedback error text={(l) => l.widget.scholarSearch.noMatches} testid={noMatchesTestid} />
	{/if}
{:else if placeholder !== undefined}{placeholder}{/if}

<style>
	.matches {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--spacing-half);
	}
</style>
