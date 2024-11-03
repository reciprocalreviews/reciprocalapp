<script lang="ts">
	import { page } from '$app/stores';
	import Page from '$lib/components/Page.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import SourceLink from '$lib/components/SourceLink.svelte';
	import Table from '$lib/components/Table.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import Tags from '$lib/components/Tags.svelte';

	let { data } = $props();
	const { venue, commitments } = $derived(data);
</script>

{#if venue === null}
	<Page title="Unknown venue">
		<Feedback>Unable to find this venue.</Feedback>
	</Page>
{:else if commitments === null}
	<Page title="Volunteers unavailable">
		<Feedback>Unable to load volunteers for this venue.</Feedback>
	</Page>
{:else}
	<Page title={venue.title} subtitle="Volunteers">
		<p>
			These are scholars that have volunteered to review for <SourceLink
				id={$page.params.id}
				name={venue.title}
			/>.
		</p>
		<Table>
			<tr>
				<th>Role</th>
				<th>Name</th>
				<th>Expertise</th>
			</tr>
			{#each commitments.toSorted((a, b) => a.roles?.name.localeCompare(b.roles?.name ?? '') ?? 0) as volunteer}
				<tr>
					<td><Tag>{volunteer.roles?.name}</Tag></td>
					<td><ScholarLink id={volunteer.scholarid} /></td>
					<td
						><Tags
							>{#each volunteer.expertise.split(',') as expertise}<Tag>{expertise}</Tag
								>{/each}</Tags
						></td
					>
				</tr>
			{/each}
		</Table>
	</Page>
{/if}
