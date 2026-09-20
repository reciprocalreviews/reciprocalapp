<script lang="ts">
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { EmptyLabel, ScholarLabel } from '$lib/components/Labels.js';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Row from '$lib/components/Row.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Status from '$lib/components/Status.svelte';
	import Table from '$lib/components/Table.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import Tags from '$lib/components/Tags.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import toCSV from '$lib/data/toCSV';
	import ORCIDKeywords from '$lib/components/ORCIDKeywords.svelte';
	import VenueExpertise from '$lib/components/VenueExpertise.svelte';
	import { getDB } from '$lib/data/CRUD';
	import {
		expertiseTags,
		orcidKeywords,
		TAG_LIMIT,
		volunteersView
	} from '$lib/data/volunteersView';
	import { anyWithheld, withholdingFor } from '$lib/data/withheldVolunteers';
	import { venueBarName } from '$lib/data/venueBarLinks';
	import Text from '$lib/locales/Text.svelte';
	import { getLocaleContext } from '$routes/Contexts';

	let { data } = $props();
	const { venue, commitments, roles, volunteerCounts } = $derived(data);

	let filter = $state('');
	/** The selected expertise chips. Held as keys rather than labels, so a selection
	 * survives a change in which spelling is commonest — and with the label it was
	 * picked under, so the chip never relabels while the reader is using it. */
	let selectedTags = $state<{ key: string; label: string }[]>([]);
	let showAllTags = $state(false);
	const locale = getLocaleContext();
	const db = getDB();

	/** The list's rules — search matching, how the expertise keywords are ranked,
	 * and the row ordering — live in $lib/data/volunteersView so they are testable
	 * outside a component. */
	const view = $derived(
		volunteersView({ filter, selected: new Map(selectedTags.map((t) => [t.key, t.label])) })
	);

	function toggleTag(key: string, label: string) {
		selectedTags = selectedTags.some((t) => t.key === key)
			? selectedTags.filter((t) => t.key !== key)
			: [...selectedTags, { key, label }];
	}

	/** One section per role, in priority order, paired with what this viewer is not
	 * being shown of it.
	 *
	 * Derived from `roles` rather than from the role ids present in `commitments`: a
	 * role whose entire roster is withheld has no rows to derive a section from, and
	 * would silently vanish from a venue that does in fact have the role. `roles` is
	 * world-readable, so reading it here discloses nothing new. A role nobody has
	 * volunteered for is still dropped — that is an absent roster, not a hidden one. */
	const sections = $derived(
		commitments === null
			? []
			: (roles ?? [])
					.toSorted((a, b) => a.priority - b.priority)
					.map((role) => ({
						role,
						withholding: withholdingFor(role.id, commitments, volunteerCounts)
					}))
					.filter(
						({ role, withholding }) =>
							commitments.some((c) => c.roleid === role.id) || withholding.all
					)
	);

	/** Whether any of this venue's rosters is withholding rows from this viewer. Drives
	 * the notice on the export and the empty-state message, both of which would
	 * otherwise say something false about a venue that has simply chosen not to publish
	 * its rosters. */
	const partial = $derived(
		commitments === null || roles === null
			? false
			: anyWithheld(
					roles.map((r) => r.id),
					commitments,
					volunteerCounts
				)
	);

	// Warm the mirror for whoever opens this roster next. Never awaited; the database
	// clamps the batch and a cooldown stops repeat readers re-asking.
	$effect(() => {
		if (commitments !== null) db().requestORCIDRefresh(commitments.map((c) => c.scholarid));
	});

	function exportCSV() {
		if (commitments === null) return;

		const headers = [
			'Name',
			'Email',
			'ORCID',
			'Role',
			'Expertise',
			// Its own column, never appended to Expertise: that column is what the volunteer
			// wrote for this venue, and merging the two would export a claim it never made.
			'ORCID keywords',
			'Papers cap',
			'Active'
		];
		const rows = commitments.map((c) => [
			c.scholars.name ?? '',
			c.scholars.email ?? '',
			c.scholars.orcid ?? '',
			c.roles.name ?? '',
			c.expertise,
			orcidKeywords(c).join(', '),
			c.papers === null ? '' : c.papers.toString(),
			c.active ? 'Yes' : 'No'
		]);

		// A Blob URL rather than a `data:` URI: encodeURI does not escape `#`, so
		// the old data URI truncated the file at the first one — a volunteer whose
		// expertise said "C#" silently lost every row after them.
		const url = URL.createObjectURL(
			new Blob([toCSV(headers, rows)], { type: 'text/csv;charset=utf-8' })
		);
		const link = document.createElement('a');
		link.setAttribute('href', url);
		link.setAttribute('download', `${venue?.title ?? 'volunteers'}.csv`);
		document.body.appendChild(link);
		link.click();
		document.body.removeChild(link);
		URL.revokeObjectURL(url);
	}
</script>

{#if venue === null}
	<Page band={false} title={(l) => l.page.venue.unknownTitle}>
		<Feedback text={(l) => l.page.volunteers.feedback.unknownVenue}></Feedback>
	</Page>
{:else if commitments === null}
	<Page band={false} title={(l) => l.page.volunteers.unavailableTitle}>
		<Feedback text={(l) => l.page.volunteers.feedback.volunteersNotLoaded}></Feedback>
	</Page>
{:else}
	<Page band={false} title={`${locale().page.volunteers.title} — ${venueBarName(venue)}`}>
		<Paragraph text={(l) => l.page.volunteers.paragraph.intro} />

		<TextField
			strings={(l) => l.page.volunteers.field.filter}
			bind:text={filter}
			testid="volunteer-filter"
		></TextField>

		{@const allTags = view.tags(commitments)}
		{#if allTags.length > 0}
			<div
				class="expertise"
				role="group"
				aria-label={locale().page.volunteers.label.expertiseFilter}
			>
				<!-- Above the keywords, not below them: expanded, the list runs to many rows,
				     and a collapse control at the bottom of it is the one thing the reader
				     has to scroll past everything to reach. -->
				{#if allTags.length > TAG_LIMIT || selectedTags.length > 0}
					<Row>
						{#if allTags.length > TAG_LIMIT}
							<Button
								small
								background={false}
								testid="volunteer-tags-more"
								strings={(l) =>
									showAllTags
										? l.page.volunteers.button.fewerTags
										: l.page.volunteers.button.moreTags}
								action={() => (showAllTags = !showAllTags)}
							/>
						{/if}
						{#if selectedTags.length > 0}
							<Button
								small
								background={false}
								testid="volunteer-tags-clear"
								strings={(l) => l.page.volunteers.button.clearTags}
								action={() => (selectedTags = [])}
							/>
						{/if}
					</Row>
				{/if}
				<Tags>
					<!-- Keyed on the tag's key so Svelte reuses the same button when the list
					     re-ranks, which is what keeps focus on the chip you just pressed. -->
					{#each showAllTags ? allTags : view.capped(allTags) as tag (tag.key)}
						<Tag
							wrap
							action={() => toggleTag(tag.key, tag.label)}
							selected={selectedTags.some((t) => t.key === tag.key)}
							testid="volunteer-tag-{tag.key}"
							><Text
								path={(l) => l.page.volunteers.label.count}
								inputs={{ name: tag.label, count: tag.count.toString() }}
							/></Tag
						>
					{/each}
				</Tags>
			</div>
		{/if}

		{#if sections.length === 0}
			<Feedback text={(l) => l.page.volunteers.feedback.noVolunteers}></Feedback>
		{:else if !commitments.some((c) => view.matchesFilter(c) && view.matchesTags(c)) && !sections.some((s) => s.withholding.all)}
			<Feedback text={(l) => l.page.volunteers.feedback.noneMatching}></Feedback>
		{:else}
			<Table full>
				{#snippet header()}
					<th>{locale().page.volunteers.headers.active}</th>
					<th>{locale().page.volunteers.headers.name}</th>
					<th>{locale().page.volunteers.headers.expertise}</th>
					<th>{locale().page.volunteers.headers.papers}</th>
				{/snippet}
				{#each sections as { role, withholding }, roleIndex (role.id)}
					{@const rows = view.sortedAndFiltered(commitments.filter((c) => c.roleid === role.id))}
					{#if rows.length > 0 || withholding.all}
						<!-- The role's own name, not `rows[0].roles.name`: a withheld roster has
						     no first row to take it from. The count stays the number of rows
						     matching the current search, as it always has; how many are withheld
						     is a separate statement below, measured against the unfiltered rows
						     so that searching never reads as withholding. -->
						<tr data-testid="volunteer-role-{roleIndex}"
							><td colspan="4"
								><strong
									>{ScholarLabel}
									<Text
										path={(l) => l.page.volunteers.label.count}
										inputs={{ name: role.name, count: rows.length.toString() }}
									/></strong
								></td
							></tr
						>
						{#if withholding.all}
							<tr data-testid="volunteer-withheld-{roleIndex}"
								><td colspan="4"
									><Text
										path={(l) => l.page.volunteers.feedback.withheldAll}
										inputs={{ count: withholding.total.toString() }}
									/></td
								></tr
							>
						{:else if withholding.withheld > 0}
							<tr data-testid="volunteer-withheld-{roleIndex}"
								><td colspan="4"
									><Text
										path={(l) => l.page.volunteers.feedback.withheld}
										inputs={{ count: withholding.withheld.toString() }}
									/></td
								></tr
							>
						{/if}
						{#each rows as volunteer, volunteerIndex (volunteer.id)}
							{@const expertise = expertiseTags(volunteer.expertise)}
							{@const mirrored = orcidKeywords(volunteer)}
							<tr data-testid="volunteer-row-{roleIndex}-{volunteerIndex}">
								<td
									><Status
										testid="volunteer-status"
										good={volunteer.active}
										label={(l) =>
											volunteer.active
												? l.page.volunteers.status.active
												: l.page.volunteers.status.inactive}
									/></td
								>
								<td><ScholarLink id={volunteer.scholarid} /></td>
								<td
									><!-- The venue's own expertise, ALWAYS answered — an em-dash when the
									     volunteer wrote none, whether or not ORCID has keywords for them.
									     Rendered as a Tags row only when there is something to put in it:
									     Tags is a block-level flex div, so an empty one still took a line
									     box and left a gap above whatever followed. -->
									{#if expertise.length > 0}
										<VenueExpertise
											>{#each expertise as topic}<Tag wrap>{topic}</Tag>{/each}</VenueExpertise
										>
									{/if}
									<!-- ORCID's keywords, below the venue's own and marked as ORCID's. Not
									     clickable: the chips above are filters over what volunteers wrote
									     for THIS venue about reviewing, and these describe a research
									     career. Searchable but never ranked — see volunteersView's `tags`. -->
									<ORCIDKeywords
										keywords={mirrored}
									/>{#if expertise.length === 0 && mirrored.length === 0}<em>{EmptyLabel}</em
										>{/if}</td
								>
								<td>{volunteer.papers === null ? EmptyLabel : volunteer.papers}</td>
							</tr>
						{/each}
					{/if}
				{/each}
			</Table>
		{/if}

		<!-- Below the list it exports, rather than above it. -->
		{#if partial}
			<!-- The export writes `commitments`, which RLS has already filtered, so it is
			     as partial as the list above it. Said out loud rather than left to be
			     discovered: a spreadsheet that looks like the whole roster is worse than a
			     short one that admits what it is. -->
			<Feedback text={(l) => l.page.volunteers.feedback.partialExport}></Feedback>
		{/if}
		<Button
			strings={(l) => l.page.volunteers.button.exportCSV}
			testid="volunteer-export-csv"
			action={exportCSV}
		/>
	</Page>
{/if}

<style>
	.expertise {
		display: flex;
		flex-direction: column;
		/* The standard gap, so the controls read as belonging to the keywords below
		   them rather than to the search field above. */
		gap: var(--spacing);
	}
</style>
