<script lang="ts">
	import Button from '#lib/components/Button.svelte';
	import Feedback from '#lib/components/Feedback.svelte';
	import { EmptyLabel, ScholarLabel } from '#lib/components/Labels.js';
	import Page from '#lib/components/Page.svelte';
	import Paragraph from '#lib/components/Paragraph.svelte';
	import Row from '#lib/components/Row.svelte';
	import ScholarPreview from '#lib/components/ScholarPreview.svelte';
	import Status from '#lib/components/Status.svelte';
	import Table from '#lib/components/Table.svelte';
	import Tag from '#lib/components/Tag.svelte';
	import Tags from '#lib/components/Tags.svelte';
	import TextField from '#lib/components/TextField.svelte';
	import toCSV from '#lib/data/toCSV.js';
	import ORCIDKeywords from '#lib/components/ORCIDKeywords.svelte';
	import LoadIndicator from '#lib/components/LoadIndicator.svelte';
	import Loads from '#lib/data/load.js';
	import VenueExpertise from '#lib/components/VenueExpertise.svelte';
	import { getDB } from '#lib/data/CRUD.js';
	import {
		expertiseTags,
		orcidKeywords,
		TAG_LIMIT,
		volunteersView,
		volunteerStanding
	} from '#lib/data/volunteersView.js';
	import { trackRecord, trackTier, venueRoles, type TrackRecord } from '#lib/data/trackRecord.js';
	import { anyWithheld, withholdingFor } from '#lib/data/withheldVolunteers.js';
	import { venueBarName } from '#lib/data/venueBarLinks.js';
	import Text from '#lib/locales/Text.svelte';
	import { getLocaleContext } from '#routes/Contexts.js';
	import { handle } from '#routes/feedback.svelte.js';

	let { data } = $props();
	const {
		venue,
		commitments,
		roles,
		volunteerCounts,
		canContact,
		canRemove,
		loads,
		completed,
		journals,
		scholar
	} = $derived(data);

	const loadIndex = $derived(new Loads(loads));

	let filter = $state('');
	/** The selected expertise chips. Held as keys rather than labels, so a selection
	 * survives a change in which spelling is commonest — and with the label it was
	 * picked under, so the chip never relabels while the reader is using it. */
	let selectedTags = $state<{ key: string; label: string }[]>([]);
	let showAllTags = $state(false);
	const locale = getLocaleContext();
	const db = getDB();

	/** Each volunteer's track record, for those who assign: vetted roles held here,
	 * reviews finished here, and works in the venue's relevant venues. Null for everyone else, who get the plain
	 * order, since an order ranked on evidence they cannot see would disclose it. */
	const records = $derived.by(() => {
		if (!canContact || venue === null) return null;
		const counts = new Map(completed.map((c) => [c.scholar, c.count]));
		const works = new Map(journals.map((j) => [j.scholar, j.journals]));
		const byScholar = new Map<string, TrackRecord>();
		for (const id of new Set((commitments ?? []).map((c) => c.scholarid)))
			byScholar.set(
				id,
				trackRecord(counts.get(id) ?? 0, works.get(id) ?? [], venue.relevant_venues, {
					roles: venueRoles(id, commitments ?? [], roles ?? []),
					admin: venue.admins.includes(id)
				})
			);
		return byScholar;
	});

	function recordOf(scholarid: string | undefined): TrackRecord | undefined {
		return scholarid === undefined ? undefined : records?.get(scholarid);
	}

	/** A track record's roles as the export writes them: "Associate Editor; former Editor". */
	function rolesText(record: TrackRecord | undefined): string {
		if (record === undefined) return '';
		const text = locale().page.volunteers.label;
		return [
			...(record.admin ? [text.admin] : []),
			...record.roles.map((r) => (r.current ? r.name : text.formerRole.replace('{role}', r.name)))
		].join('; ');
	}

	function tierOf(scholarid: string | undefined) {
		const record = recordOf(scholarid);
		return record === undefined ? 2 : trackTier(record);
	}

	/** Suggested by default when there is anything to suggest on: a venue with relevant
	 * venues set, or anyone who has finished work here. A new venue with neither would
	 * otherwise open on an empty list. Null until the reader chooses. */
	let chosenView = $state<'suggested' | 'everyone' | null>(null);
	const suggestedOnly = $derived(
		records !== null &&
			(chosenView === null
				? (venue?.relevant_venues.length ?? 0) > 0 || completed.length > 0
				: chosenView === 'suggested')
	);

	/** The list's rules — search matching, how the expertise keywords are ranked,
	 * and the row ordering — live in $lib/data/volunteersView so they are testable
	 * outside a component. */
	const view = $derived(
		volunteersView({
			filter,
			selected: new Map(selectedTags.map((t) => [t.key, t.label])),
			tier: records === null ? undefined : (v) => tierOf(v.scholarid),
			suggestedOnly
		})
	);

	/** Both views' counts, under the current search and chips, so the choice says what
	 * each side holds. */
	const everyoneCount = $derived(
		(commitments ?? []).filter((c) => view.matchesFilter(c) && view.matchesTags(c)).length
	);
	const suggestedCount = $derived(
		(commitments ?? []).filter(
			(c) => view.matchesFilter(c) && view.matchesTags(c) && tierOf(c.scholarid) < 2
		).length
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

		// Addresses only for those who assign others, as in the table.
		const headers = [
			'Name',
			...(canContact ? ['Email'] : []),
			'ORCID',
			'Role',
			'Expertise',
			// Its own column, never appended to Expertise: that column is what the volunteer
			// wrote for this venue, and merging the two would export a claim it never made.
			'ORCID keywords',
			'Papers cap',
			// Those who may contact volunteers are the ones choosing whom to invite.
			...(canContact
				? ['Active assignments', 'Venue roles', 'Reviewed here', 'Relevant venue works']
				: []),
			'Active'
		];
		const rows = commitments.map((c) => [
			c.scholars.name ?? '',
			...(canContact ? [c.scholars.email ?? ''] : []),
			c.scholars.orcid ?? '',
			c.roles.name ?? '',
			c.expertise,
			orcidKeywords(c).join(', '),
			c.papers === null ? '' : c.papers.toString(),
			...(canContact
				? [
						loadIndex.of(c.scholarid, c.roleid, c.papers).used.toString(),
						rolesText(recordOf(c.scholarid)),
						(recordOf(c.scholarid)?.completed ?? 0).toString(),
						(recordOf(c.scholarid)?.venueWorks ?? 0).toString()
					]
				: []),
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
	<Page title={(l) => l.page.venue.unknownTitle}>
		<Feedback text={(l) => l.page.volunteers.feedback.unknownVenue}></Feedback>
	</Page>
{:else if commitments === null}
	<Page title={(l) => l.page.volunteers.unavailableTitle}>
		<Feedback text={(l) => l.page.volunteers.feedback.volunteersNotLoaded}></Feedback>
	</Page>
{:else}
	<Page title={(l) => l.page.volunteers.title} context={venueBarName(venue)}>
		<Paragraph text={(l) => l.page.volunteers.paragraph.intro} />

		<TextField
			strings={(l) => l.page.volunteers.field.filter}
			bind:text={filter}
			testid="volunteer-filter"
		></TextField>

		{#if records !== null}
			<Paragraph text={(l) => l.page.volunteers.paragraph.suggested} />
			<div role="group" aria-label={locale().page.volunteers.label.view}>
				<Tags>
					<Tag
						action={() => (chosenView = 'suggested')}
						selected={suggestedOnly}
						testid="volunteer-view-suggested"
						><Text
							path={(l) => l.page.volunteers.label.suggested}
							inputs={{ count: suggestedCount.toString() }}
						/></Tag
					>
					<Tag
						action={() => (chosenView = 'everyone')}
						selected={!suggestedOnly}
						testid="volunteer-view-everyone"
						><Text
							path={(l) => l.page.volunteers.label.everyone}
							inputs={{ count: everyoneCount.toString() }}
						/></Tag
					>
				</Tags>
			</div>
		{/if}

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
					<th
						>{canContact
							? locale().page.volunteers.headers.assigned
							: locale().page.volunteers.headers.papers}</th
					>
				{/snippet}
				{#each sections as { role, withholding }, roleIndex (role.id)}
					{@const roleRows = commitments.filter((c) => c.roleid === role.id)}
					{@const rows = view.sortedAndFiltered(roleRows)}
					{@const hidden = view.hiddenBySuggestion(roleRows)}
					{#if rows.length > 0 || withholding.all || hidden > 0}
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
							{@const record = recordOf(volunteer.scholarid)}
							{@const previous = rows[volunteerIndex - 1]}
							<!-- In Everyone, where those with a track record end and those without
							     begin, among volunteers of the same standing. -->
							{#if record !== undefined && previous !== undefined && tierOf(volunteer.scholarid) === 2 && tierOf(previous.scholarid) < 2 && volunteerStanding(previous) === volunteerStanding(volunteer)}
								<tr data-testid="volunteer-no-record-{roleIndex}"
									><td colspan="4"
										><em><Text path={(l) => l.page.volunteers.label.noTrackRecord} /></em></td
									></tr
								>
							{/if}
							<tr data-testid="volunteer-row-{roleIndex}-{volunteerIndex}">
								<td
									><Status
										testid="volunteer-status"
										good={volunteer.active && volunteer.accepted === 'accepted'}
										neutral={volunteer.accepted !== 'accepted'}
										label={(l) =>
											volunteer.accepted === 'invited'
												? l.page.volunteers.status.invited
												: volunteer.accepted === 'declined'
													? l.page.volunteers.status.declined
													: volunteer.active
														? l.page.volunteers.status.active
														: l.page.volunteers.status.inactive}
									/>{#if canRemove && volunteer.accepted === 'accepted' && volunteer.active && volunteer.scholarid !== scholar?.id}
										<Button
											small
											testid="volunteer-remove"
											strings={(l) => l.page.volunteers.button.remove}
											action={() => handle(db().removeVolunteer(volunteer.id))}
										/>
									{/if}</td
								>
								<td
									><!-- The address for those who assign others, so they can reach a
									     volunteer who has not bid on anything; the iD and ORCID line for
									     everyone, as in the export. -->
									<ScholarPreview
										scholar={volunteer.scholars.name
											? { id: volunteer.scholarid, name: volunteer.scholars.name }
											: volunteer.scholarid}
										email={canContact ? (volunteer.scholars.email ?? null) : undefined}
										orcid={volunteer.scholars.orcid ?? null}
										profile={volunteer.scholars.orcid_profiles}
										testid="volunteer"
									/>{#if record !== undefined}
										<!-- Not the role this row is listed under: an Associate Editor's
										     row in that section saying "Associate Editor" says nothing. -->
										{@const otherRoles = record.roles.filter((r) => r.role !== volunteer.roleid)}
										{#if otherRoles.length > 0 || record.admin || record.completed > 0 || record.venueWorks > 0}
											<div class="track" data-testid="volunteer-track">
												{#if record.admin}
													<span class="badge" data-testid="volunteer-admin"
														><Text path={(l) => l.page.volunteers.label.admin} /></span
													>
												{/if}
												{#each otherRoles as held}
													<span class="badge" data-testid="volunteer-role-held"
														><Text
															path={(l) =>
																held.current
																	? l.page.volunteers.label.currentRole
																	: l.page.volunteers.label.formerRole}
															inputs={{ role: held.name }}
														/></span
													>
												{/each}
												{#if record.completed > 0}
													<span class="badge" data-testid="volunteer-reviewed-here"
														><Text
															path={(l) => l.page.volunteers.label.reviewedHere}
															inputs={{ count: record.completed.toString() }}
														/></span
													>
												{/if}
												{#if record.venueWorks > 0}
													<!-- The matched titles behind a native popover, so an editor can
												     catch a false match without the list growing a line per row. -->
													<button
														type="button"
														class="badge published"
														popovertarget="track-{volunteer.id}"
														data-testid="volunteer-published"
														><Text
															path={(l) => l.page.volunteers.label.publishedRelevant}
															inputs={{ count: record.venueWorks.toString() }}
														/></button
													>
													<div class="titles" popover id="track-{volunteer.id}">
														<p><Text path={(l) => l.page.volunteers.label.matchedTitles} /></p>
														<ul>
															{#each record.venueJournals as journal}
																<li>{journal.journal} ×{journal.count}</li>
															{/each}
														</ul>
														<p>
															<em><Text path={(l) => l.page.volunteers.label.matchedSource} /></em>
														</p>
													</div>
												{/if}
											</div>
										{/if}
									{/if}</td
								>
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
								<!-- What they already have beside the cap, for those choosing whom to
								     invite; the cap alone for everyone else. -->
								<td
									>{#if canContact}<LoadIndicator
											load={loadIndex.of(volunteer.scholarid, volunteer.roleid, volunteer.papers)}
										/>{:else}{volunteer.papers === null ? EmptyLabel : volunteer.papers}{/if}</td
								>
							</tr>
						{/each}
						{#if hidden > 0}
							<tr data-testid="volunteer-hidden-{roleIndex}"
								><td colspan="4"
									><Text
										path={(l) => l.page.volunteers.feedback.hiddenBySuggestion}
										inputs={{ count: hidden.toString() }}
									/>
									<Button
										small
										background={false}
										testid="volunteer-show-everyone"
										strings={(l) => l.page.volunteers.button.showEveryone}
										action={() => (chosenView = 'everyone')}
									/></td
								></tr
							>
						{/if}
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
	.track {
		display: flex;
		flex-wrap: wrap;
		gap: var(--spacing-half);
		margin-top: var(--spacing-half);
	}

	.badge {
		font-family: inherit;
		font-size: var(--extra-small-font-size);
		font-weight: bold;
		padding: 0 var(--spacing-half);
		border: none;
		border-radius: var(--roundedness);
		background: var(--salient-color-faded);
		color: var(--salient-color);
	}

	.badge.published {
		background: var(--focus-color-faded);
		color: var(--focus-color);
		cursor: pointer;
	}

	.badge.published:focus-visible {
		outline: var(--thick-border-width) solid var(--focus-color);
	}

	.titles {
		max-width: 30rem;
		padding: var(--spacing);
		border: var(--border-width) solid var(--border-color);
		border-radius: var(--roundedness);
		background: var(--background-color);
		color: var(--text-color);
		font-size: var(--small-font-size);
	}

	.titles p,
	.titles ul {
		margin: 0 0 var(--spacing-half);
	}

	.expertise {
		display: flex;
		flex-direction: column;
		/* The standard gap, so the controls read as belonging to the keywords below
		   them rather than to the search field above. */
		gap: var(--spacing);
	}
</style>
