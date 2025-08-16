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
	import { EmptyLabel } from '$lib/components/Labels.js';

	let { data } = $props();
	const { venue, commitments, roles } = $derived(data);
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
		{@const rolesIDs = [...new Set(commitments.map((c) => c.roleid))].toSorted(
			(a, b) =>
				(roles?.find((r) => r.id === a)?.priority ?? 0) -
				(roles?.find((r) => r.id === b)?.priority ?? 0)
		)}
		{#each rolesIDs as role}
			{@const roleCommitments = commitments.filter((c) => c.roleid === role)}
			<h2>{roleCommitments[0].roles.name}</h2>
			<Table full>
				{#snippet header()}
					<th>Active</th>
					<th>Name</th>
					<th>Expertise</th>
				{/snippet}
				{#each roleCommitments.toSorted((a, b) => a.roles?.name.localeCompare(b.roles?.name ?? '') ?? 0) as volunteer}
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
		{:else}
			<Feedback>No volunteers yet.</Feedback>
		{/each}
	</Page>
{/if}
