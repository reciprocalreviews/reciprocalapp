<script lang="ts">
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { EmptyLabel, ErrorLabel, ScholarLabel, VenueLabel } from '$lib/components/Labels.js';
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
	import { expertiseTags, TAG_LIMIT, volunteersView } from '$lib/data/volunteersView';
	import Text from '$lib/locales/Text.svelte';
	import { getLocaleContext } from '$routes/Contexts';

	let { data } = $props();
	const { venue, commitments, roles } = $derived(data);

	let filter = $state('');
	/** The selected expertise chips. Held as keys rather than labels, so a selection
	 * survives a change in which spelling is commonest — and with the label it was
	 * picked under, so the chip never relabels while the reader is using it. */
	let selectedTags = $state<{ key: string; label: string }[]>([]);
	let showAllTags = $state(false);
	const locale = getLocaleContext();

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

	function exportCSV() {
		if (commitments === null) return;

		const headers = ['Name', 'Email', 'ORCID', 'Role', 'Expertise', 'Papers cap', 'Active'];
		const rows = commitments.map((c) => [
			c.scholars.name ?? '',
			c.scholars.email ?? '',
			c.scholars.orcid ?? '',
			c.roles.name ?? '',
			c.expertise,
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
	<Page icon={ErrorLabel} title={(l) => l.page.venue.unknownTitle}>
		<Feedback text={(l) => l.page.volunteers.feedback.unknownVenue}></Feedback>
	</Page>
{:else if commitments === null}
	<Page icon={ErrorLabel} title={(l) => l.page.volunteers.unavailableTitle}>
		<Feedback text={(l) => l.page.volunteers.feedback.volunteersNotLoaded}></Feedback>
	</Page>
{:else}
	<Page icon={VenueLabel} title={venue.title}>
		{#snippet subtitle()}<Text path={(l) => l.page.volunteers.subtitle} />{/snippet}
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

		{@const rolesIDs = [...new Set(commitments.map((c) => c.roleid))].toSorted(
			(a, b) =>
				(roles?.find((r) => r.id === a)?.priority ?? 0) -
				(roles?.find((r) => r.id === b)?.priority ?? 0)
		)}

		{#if rolesIDs.length === 0}
			<Feedback text={(l) => l.page.volunteers.feedback.noVolunteers}></Feedback>
		{:else if !commitments.some((c) => view.matchesFilter(c) && view.matchesTags(c))}
			<Feedback text={(l) => l.page.volunteers.feedback.noneMatching}></Feedback>
		{:else}
			<Table full>
				{#snippet header()}
					<th>{locale().page.volunteers.headers.active}</th>
					<th>{locale().page.volunteers.headers.name}</th>
					<th>{locale().page.volunteers.headers.expertise}</th>
					<th>{locale().page.volunteers.headers.papers}</th>
				{/snippet}
				{#each rolesIDs as role, roleIndex (role)}
					{@const rows = view.sortedAndFiltered(commitments.filter((c) => c.roleid === role))}
					{#if rows.length > 0}
						<tr data-testid="volunteer-role-{roleIndex}"
							><td colspan="4"
								><strong
									>{ScholarLabel}
									<Text
										path={(l) => l.page.volunteers.label.count}
										inputs={{ name: rows[0].roles?.name ?? '', count: rows.length.toString() }}
									/></strong
								></td
							></tr
						>
						{#each rows as volunteer, volunteerIndex (volunteer.id)}
							{@const expertise = expertiseTags(volunteer.expertise)}
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
									><Tags
										>{#each expertise as topic}<Tag wrap>{topic}</Tag>{:else}<em>{EmptyLabel}</em
											>{/each}</Tags
									></td
								>
								<td>{volunteer.papers === null ? EmptyLabel : volunteer.papers}</td>
							</tr>
						{/each}
					{/if}
				{/each}
			</Table>
		{/if}

		<!-- Below the list it exports, rather than above it. -->
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
