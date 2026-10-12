<script lang="ts">
	import {
		matchPersonName,
		searchCandidates,
		suggestCandidates,
		type Volunteer
	} from '#lib/data/matchPersonName.js';
	import Text from '#lib/locales/Text.svelte';
	import Button from './Button.svelte';
	import Feedback from './Feedback.svelte';
	import ORCIDiD from './ORCIDiD.svelte';
	import ScholarLink from './ScholarLink.svelte';
	import TextField from './TextField.svelte';

	/** Choosing which of a role's volunteers a written name means. The volunteers are a
	 * closed list, the same one the database will seat, so nothing here can choose
	 * someone it would refuse. Names that tie are offered together, near misses are
	 * ranked, and anyone else is a search away; each person carries their email, ORCID
	 * iD and affiliation, and a profile link that opens in a new tab, so two people who
	 * share a name can be told apart without losing the choice in progress. */
	let {
		name,
		role,
		candidates,
		chosen,
		choose,
		clear = undefined,
		testid
	}: {
		/** The name as it was written, which suggestions are ranked against. */
		name: string;
		/** The role's name, for the labels. */
		role: string;
		/** The role's accepted, active volunteers. */
		candidates: Volunteer[];
		/** The id of the volunteer chosen, if any. */
		chosen: string | undefined;
		choose: (id: string) => void;
		/** Undoes the choice. Without it, a choice is shown but cannot be changed here. */
		clear?: (() => void) | undefined;
		testid: string;
	} = $props();

	/** How many search results to show at once. A large venue's role can have
	 * thousands of volunteers, and a longer list is no easier to read than a
	 * narrower query. */
	const SHOWN = 10;

	let query = $state('');

	const chosenVolunteer = $derived(candidates.find((c) => c.id === chosen));

	const match = $derived(matchPersonName(name, candidates));
	const ambiguous = $derived(match.status === 'ambiguous');
	const suggestions = $derived(
		match.status === 'ambiguous'
			? candidates.filter((c) => match.candidates.some((m) => m.id === c.id))
			: suggestCandidates(name, candidates)
	);
	const results = $derived(searchCandidates(query, candidates));
</script>

{#snippet details(volunteer: Volunteer)}
	<span class="details">
		{#if volunteer.email}<span>{volunteer.email}</span>{/if}
		{#if volunteer.orcid}<ORCIDiD id={volunteer.orcid} />{:else}<span
				><Text path={(l) => l.widget.volunteerPicker.noORCID} /></span
			>{/if}
		{#if volunteer.affiliation}<span>{volunteer.affiliation}</span>{/if}
	</span>
{/snippet}

{#snippet option(volunteer: Volunteer)}
	<li class="option">
		<Button
			small
			testid="{testid}-choose-{volunteer.id}"
			strings={(l) => ({
				label: l.widget.scholarSearch.choose.label,
				// The tip is the button's aria-label, and a column of buttons that all
				// say "Choose" is unusable by voice or screen reader.
				tip: l.widget.scholarSearch.choose.tip.replace('{name}', volunteer.name)
			})}
			action={() => {
				query = '';
				choose(volunteer.id);
			}}
		/>
		<span class="who">
			<ScholarLink id={volunteer} size="small" newTab />
			{@render details(volunteer)}
		</span>
	</li>
{/snippet}

<div class="picker" data-testid={testid}>
	{#if chosenVolunteer !== undefined}
		<div class="chosen" data-testid="{testid}-chosen">
			<span class="who">
				<ScholarLink id={chosenVolunteer} size="small" newTab />
				{@render details(chosenVolunteer)}
			</span>
			{#if clear !== undefined}
				<Button
					small
					testid="{testid}-change"
					strings={(l) => l.widget.volunteerPicker.change}
					action={clear}
				/>
			{/if}
		</div>
	{:else}
		{#if query.trim() === ''}
			{#if suggestions.length > 0}
				<span class="heading">
					<Text
						path={(l) =>
							ambiguous ? l.widget.volunteerPicker.ambiguous : l.widget.volunteerPicker.suggestions}
						inputs={{ name, role }}
					/>
				</span>
				<ul>
					{#each suggestions as volunteer (volunteer.id)}
						{@render option(volunteer)}
					{/each}
				</ul>
			{:else}
				<Feedback text={(l) => l.widget.volunteerPicker.noSuggestions} inputs={{ role }} />
			{/if}
		{/if}
		<TextField
			stretch
			bind:text={query}
			testid="{testid}-search"
			strings={(l) => ({
				...l.widget.volunteerPicker.search,
				label: (l.widget.volunteerPicker.search.label ?? '')
					.replaceAll('{role}', role)
					.replaceAll('{count}', candidates.length.toString())
			})}
		/>
		{#if query.trim() !== ''}
			{#if results.length === 0}
				<Feedback
					testid="{testid}-no-results"
					text={(l) => l.widget.volunteerPicker.noResults}
					inputs={{ role, query: query.trim() }}
				/>
			{:else}
				<ul>
					{#each results.slice(0, SHOWN) as volunteer (volunteer.id)}
						{@render option(volunteer)}
					{/each}
				</ul>
				{#if results.length > SHOWN}
					<span class="details">
						<Text
							path={(l) => l.widget.volunteerPicker.more}
							inputs={{ shown: SHOWN.toString(), count: results.length.toString() }}
						/>
					</span>
				{/if}
			{/if}
		{/if}
	{/if}
</div>

<style>
	.picker {
		display: flex;
		flex-direction: column;
		gap: var(--spacing-half);
		min-width: 16rem;
	}

	.heading {
		font-size: var(--small-font-size);
		font-style: italic;
	}

	ul {
		list-style: none;
		margin: 0;
		padding: 0;
	}

	.option {
		display: flex;
		gap: var(--spacing-half);
		align-items: baseline;
		padding: var(--spacing-half) 0;
		border-top: var(--border-width) solid var(--border-color);
	}

	.who {
		display: flex;
		flex-direction: column;
	}

	.chosen {
		display: flex;
		gap: var(--spacing-half);
		align-items: baseline;
		justify-content: space-between;
		padding: var(--spacing-half);
		border: var(--border-width) solid var(--salient-color);
		border-radius: var(--roundedness);
		background: var(--salient-color-faded);
	}

	/* The email, iD and affiliation are what tell two people with one name apart, so
	   they are always visible, just quieter than the name. */
	.details {
		display: flex;
		flex-wrap: wrap;
		column-gap: var(--spacing-half);
		font-size: var(--extra-small-font-size);
	}
</style>
