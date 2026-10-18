<script lang="ts">
	import {
		matchPersonName,
		searchCandidates,
		suggestCandidates,
		type Volunteer
	} from '#lib/data/matchPersonName.js';
	import Text from '#lib/locales/Text.svelte';
	import { tick } from 'svelte';
	import Button from './Button.svelte';
	import Feedback from './Feedback.svelte';
	import ScholarLink from './ScholarLink.svelte';
	import ScholarPreview from './ScholarPreview.svelte';
	import TextField from './TextField.svelte';

	/** Choosing which of a role's volunteers a written name means. The volunteers are a
	 * closed list, the same one the database will seat, so nothing here can choose
	 * someone it would refuse.
	 *
	 * It is built to be repeated hundreds of times down a page — once per unmatched name,
	 * once per cell of an import — so it stays short. Names that tie are offered with
	 * everything that tells them apart; near misses get one line each, and only when
	 * they are within a couple of typos; anyone else is behind a search that stays
	 * closed until asked for. The person chosen gets the same ScholarPreview as every
	 * other display, and every name links to a profile that opens in a new tab, so
	 * checking who someone is never loses the choice in progress. */
	let {
		name,
		role,
		candidates,
		chosen,
		choose,
		clear = undefined,
		testid
	}: {
		/** The name as it was written, which suggestions are matched against. */
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

	let searching = $state(false);
	let query = $state('');
	let field = $state<HTMLInputElement | HTMLTextAreaElement | undefined>(undefined);

	const chosenVolunteer = $derived(candidates.find((c) => c.id === chosen));

	const match = $derived(matchPersonName(name, candidates));
	/** The volunteers the name fits equally well, who need everything that tells
	 * them apart, since their names do not. */
	const tied = $derived(
		match.status === 'ambiguous'
			? candidates.filter((c) => match.candidates.some((m) => m.id === c.id))
			: []
	);
	const suggestions = $derived(tied.length > 0 ? [] : suggestCandidates(name, candidates));
	const results = $derived(searchCandidates(query, candidates));

	async function openSearch() {
		searching = true;
		await tick();
		field?.focus();
	}

	function pick(volunteer: Volunteer) {
		query = '';
		searching = false;
		choose(volunteer.id);
	}
</script>

<!-- Everything that tells two people with one name apart, for the tied and the chosen. -->
{#snippet preview(volunteer: Volunteer)}
	<ScholarPreview
		scholar={volunteer}
		email={volunteer.email}
		orcid={volunteer.orcid}
		profile={volunteer.profile}
		size="small"
		newTab
	/>
{/snippet}

{#snippet chooseButton(volunteer: Volunteer)}
	<Button
		small
		testid="{testid}-choose-{volunteer.id}"
		strings={(l) => ({
			label: l.widget.scholarSearch.choose.label,
			// The tip is the button's aria-label, and a column of buttons that all
			// say "Choose" is unusable by voice or screen reader.
			tip: l.widget.scholarSearch.choose.tip.replace('{name}', volunteer.name)
		})}
		action={() => pick(volunteer)}
	/>
{/snippet}

<!-- One line: the name, and the email beside it, which is usually enough to tell
     near misses apart. The full details wait until someone is chosen. -->
{#snippet line(volunteer: Volunteer)}
	<li class="option">
		{@render chooseButton(volunteer)}
		<span class="name"><ScholarLink id={volunteer} size="small" newTab /></span>
		{#if volunteer.email}<span class="email">{volunteer.email}</span>{/if}
	</li>
{/snippet}

<div class="picker" data-testid={testid}>
	{#if chosenVolunteer !== undefined}
		<div class="chosen" data-testid="{testid}-chosen">
			{@render preview(chosenVolunteer)}
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
		<!-- A search in progress replaces the offers rather than adding to them, so the
		     same person is never listed twice. -->
		{#if searching && query.trim() !== ''}
			<!-- Nothing here; the results follow the field. -->
		{:else if tied.length > 0}
			<span class="heading">
				<Text path={(l) => l.widget.volunteerPicker.ambiguous} inputs={{ name, role }} />
			</span>
			<ul>
				{#each tied as volunteer (volunteer.id)}
					<li class="option tied">
						{@render chooseButton(volunteer)}
						{@render preview(volunteer)}
					</li>
				{/each}
			</ul>
		{:else if suggestions.length > 0}
			<span class="heading">
				<Text path={(l) => l.widget.volunteerPicker.suggestions} inputs={{ role }} />
			</span>
			<ul>
				{#each suggestions as volunteer (volunteer.id)}
					{@render line(volunteer)}
				{/each}
			</ul>
		{:else}
			<span class="heading">
				<Text path={(l) => l.widget.volunteerPicker.noSuggestions} inputs={{ role }} />
			</span>
		{/if}
		{#if searching}
			<TextField
				stretch
				bind:text={query}
				bind:view={field}
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
							{@render line(volunteer)}
						{/each}
					</ul>
					{#if results.length > SHOWN}
						<span class="heading">
							<Text
								path={(l) => l.widget.volunteerPicker.more}
								inputs={{ shown: SHOWN.toString(), count: results.length.toString() }}
							/>
						</span>
					{/if}
				{/if}
			{/if}
		{:else}
			<span class="open">
				<Button
					small
					background={false}
					testid="{testid}-search-open"
					strings={(l) => ({
						label: l.widget.volunteerPicker.openSearch.label.replaceAll('{role}', role),
						tip: l.widget.volunteerPicker.openSearch.tip
							.replaceAll('{role}', role)
							.replaceAll('{count}', candidates.length.toString())
					})}
					action={openSearch}
				/>
			</span>
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
		padding: calc(var(--spacing-half) / 2) 0;
		min-width: 0;
	}

	.option.tied {
		padding: var(--spacing-half) 0;
		border-top: var(--border-width) solid var(--border-color);
	}

	/* Links wrap by default (app.html), and a name broken across two lines reads as
	   two people; the email beside it gives way instead. ScholarPreview does the same
	   for the tied and the chosen. */
	.name,
	.name :global(a) {
		white-space: nowrap;
	}

	.option .name {
		flex: none;
	}

	/* Truncated rather than wrapped, so a near miss stays one line however long the
	   address: the line is for recognizing someone, and the chosen card shows it all. */
	.email {
		font-size: var(--extra-small-font-size);
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.open {
		align-self: flex-start;
	}

	/* The same plain preview as everywhere else; Change beside it is what says the name
	   has been resolved, and that it can be undone. */
	.chosen {
		display: flex;
		gap: var(--spacing-half);
		align-items: flex-start;
		justify-content: space-between;
	}
</style>
