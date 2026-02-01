<script lang="ts">
	import { page } from '$app/state';
	import Page from '$lib/components/Page.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import SourceLink from '$lib/components/VenueLink.svelte';
	import Table from '$lib/components/Table.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import Tags from '$lib/components/Tags.svelte';
	import Status from '$lib/components/Status.svelte';
	import { EmptyLabel, FilterLabel, ScholarLabel } from '$lib/components/Labels.js';
	import TextField from '$lib/components/TextField.svelte';
	import Button from '$lib/components/Button.svelte';
	import Subheader from '$lib/components/Subheader.svelte';

	let { data } = $props();
	const { venue, commitments, roles } = $derived(data);

	let filter = $state('');

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
	<Page title="Unknown venue" breadcrumbs={[]}>
		<Feedback>Unable to find this venue.</Feedback>
	</Page>
{:else if commitments === null}
	<Page title="Volunteers unavailable" breadcrumbs={[[`/${venue.id}`, venue.title]]}>
		<Feedback>Unable to load volunteers for this venue.</Feedback>
	</Page>
{:else}
	<Page
		title={venue.title}
		breadcrumbs={[
			['/venues', 'Venues'],
			[`/venue/${venue.id}`, venue.title]
		]}
	>
		{#snippet subtitle()}Volunteers{/snippet}
		<p>
			These are scholars that have volunteered to review for <SourceLink
				id={page.params.id ?? ''}
				name={venue.title}
			/>.
		</p>

		<TextField label="{FilterLabel} filter" placeholder="name, expertise, email" bind:text={filter}
		></TextField>

		<Button
			tip="Export the volunteer names, emails, ORCIDs, roles, expertise, and status as a CSV"
			action={exportCSV}>Export to CSV...</Button
		>

		{@const rolesIDs = [...new Set(commitments.map((c) => c.roleid))].toSorted(
			(a, b) =>
				(roles?.find((r) => r.id === a)?.priority ?? 0) -
				(roles?.find((r) => r.id === b)?.priority ?? 0)
		)}
		{#each rolesIDs as role}
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
				<Subheader icon={ScholarLabel}>{filteredScholars[0].roles?.name}</Subheader>
				<Table full>
					{#snippet header()}
						<th>Active</th>
						<th>Name</th>
						<th>Expertise</th>
					{/snippet}
					{#each filteredScholars.toSorted((a, b) => a.roles?.name.localeCompare(b.roles?.name ?? '') ?? 0) as volunteer}
						{@const expertise = volunteer.expertise.split(',').filter((s) => s.trim() !== '')}
						<tr>
							<td
								><Status good={volunteer.active}
									>{#if volunteer.active}active{:else}inactive{/if}</Status
								></td
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
				</Table>
			{/if}
		{:else}
			<Feedback>No volunteers yet.</Feedback>
		{/each}
	</Page>
{/if}
