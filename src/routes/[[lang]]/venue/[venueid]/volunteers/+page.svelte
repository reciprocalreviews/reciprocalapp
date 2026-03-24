<script lang="ts">
	import { page } from '$app/state';
	import Text from '$lib/locales/Text.svelte';
	import Page from '$lib/components/Page.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import VenueLink from '$lib/components/VenueLink.svelte';
	import Table from '$lib/components/Table.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import Tags from '$lib/components/Tags.svelte';
	import Status from '$lib/components/Status.svelte';
	import { EmptyLabel, ErrorLabel, ScholarLabel, VenueLabel } from '$lib/components/Labels.js';
	import TextField from '$lib/components/TextField.svelte';
	import Button from '$lib/components/Button.svelte';
	import { getLocaleContext } from '$routes/Contexts';

	let { data } = $props();
	const { venue, commitments, roles } = $derived(data);

	let filter = $state('');
	const locale = getLocaleContext();

	function exportCSV() {
		if (commitments === null) return;

		const headers = ['Name', 'Email', 'ORCID', 'Role', 'Expertise', 'Active'];
		const rows = commitments.map((c) => [
			c.scholars.name ?? '',
			c.scholars.email ?? '',
			c.scholars.orcid ?? '',
			c.roles.name ?? '',
			c.expertise,
			c.active ? 'Yes' : 'No'
		]);

		const csvContent =
			'data:text/csv;charset=utf-8,' +
			[headers, ...rows]
				.map((e) => e.map((v) => `"${v.replace(/"/g, '""')}"`).join(','))
				.join('\n');

		const encodedUri = encodeURI(csvContent);
		const link = document.createElement('a');
		link.setAttribute('href', encodedUri);
		link.setAttribute('download', `${venue?.title ?? 'volunteers'}.csv`);
		document.body.appendChild(link);
		link.click();
		document.body.removeChild(link);
	}
</script>

{#if venue === null}
	<Page icon={ErrorLabel} title={(l) => l.page.venue.unknownTitle} breadcrumbs={[]}>
		<Feedback text={(l) => l.page.volunteers.feedback.unknownVenue}></Feedback>
	</Page>
{:else if commitments === null}
	<Page
		icon={ErrorLabel}
		title={(l) => l.page.volunteers.unavailableTitle}
		breadcrumbs={[[`/${venue.id}`, venue.title]]}
	>
		<Feedback text={(l) => l.page.volunteers.feedback.volunteersNotLoaded}></Feedback>
	</Page>
{:else}
	<Page icon={VenueLabel} title={venue.title} breadcrumbs={[[`/venue/${venue.id}`, venue.title]]}>
		{#snippet subtitle()}<Text path={(l) => l.page.volunteers.subtitle} />{/snippet}
		<p>
			These are scholars that have volunteered to review for <VenueLink
				id={page.params.venueid ?? ''}
				name={venue.title}
			/>.
		</p>

		<TextField strings={(l) => l.page.volunteers.field.filter} bind:text={filter}></TextField>

		<Button strings={(l) => l.page.volunteers.button.exportCSV} action={exportCSV} />

		{@const rolesIDs = [...new Set(commitments.map((c) => c.roleid))].toSorted(
			(a, b) =>
				(roles?.find((r) => r.id === a)?.priority ?? 0) -
				(roles?.find((r) => r.id === b)?.priority ?? 0)
		)}

		{#if rolesIDs.length === 0}
			<Feedback text={(l) => l.page.volunteers.feedback.noVolunteers}></Feedback>
		{:else}
			<Table full>
				{#snippet header()}
					<th>{locale.page.volunteers.headers.active}</th>
					<th>{locale.page.volunteers.headers.name}</th>
					<th>{locale.page.volunteers.headers.expertise}</th>
				{/snippet}
				{#each rolesIDs as role, roleIndex}
					{@const roleCommitments = commitments.filter((c) => c.roleid === role)}
					{@const filteredScholars =
						filter.length === 0
							? roleCommitments
							: roleCommitments.filter(
									(c) =>
										c.scholars.name?.toLowerCase().includes(filter.toLowerCase()) ||
										c.expertise.toLowerCase().includes(filter.toLowerCase()) ||
										c.scholars.email?.toLowerCase().includes(filter.toLowerCase())
								)}
					{#if filteredScholars.length > 0}
						<tr
							><td colspan="3"><strong>{ScholarLabel} {filteredScholars[0].roles?.name}</strong></td
							></tr
						>
						{#each filteredScholars.toSorted((a, b) => a.roles?.name.localeCompare(b.roles?.name ?? '') ?? 0) as volunteer, volunteerIndex}
							{@const expertise = volunteer.expertise.split(',').filter((s) => s.trim() !== '')}
							<tr data-testid="volunteer-row-{roleIndex}-{volunteerIndex}">
								<td
									><Status
										good={volunteer.active}
										label={(l) => volunteer.active ? l.page.volunteers.status.active : l.page.volunteers.status.inactive}
									/></td
								>
								<td><ScholarLink id={volunteer.scholarid} /></td>
								<td
									><Tags
										>{#each expertise as topic}<Tag>{topic}</Tag>{:else}<em>{EmptyLabel}</em
											>{/each}</Tags
									></td
								>
							</tr>
						{/each}
					{/if}
				{/each}
			</Table>
		{/if}
	</Page>
{/if}
