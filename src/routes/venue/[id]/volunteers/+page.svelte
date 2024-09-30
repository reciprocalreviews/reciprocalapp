<script lang="ts">
	import { page } from '$app/stores';
	import { getDB } from '$lib/data/Database';
	import Feedback from '$lib/components/Feedback.svelte';
	import Loading from '$lib/components/Loading.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import SourceLink from '$lib/components/SourceLink.svelte';
	import Table from '$lib/components/Table.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import Tags from '$lib/components/Tags.svelte';
	import Status from '$lib/components/Status.svelte';
	import Todo from '$lib/components/Todo.svelte';

	const db = getDB();
	$: sourceID = $page.params.id;
	$: volunteersPromise = db.getSourceVolunteers(sourceID);
</script>

{#await volunteersPromise}
	<h1>Volunteers</h1>
	<Loading />
{:then volunteers}
	<h1>Volunteers</h1>

	<p>
		These are scholars that have volunteered to review for <SourceLink id={$page.params.id} />,
		sorted by the number of reviews they are seeking.
	</p>

	<Todo>List of scholars.</Todo>

	<!-- <Table>
		{#each volunteers.sort((a, b) => a.balance - b.balance) as volunteer}
			<tr>
				<td><ScholarLink id={volunteer.scholar} /></td>
				<td
					><Status good={volunteer.balance < volunteer.scholar.minimum}
						>{#if volunteer.balance < volunteer.scholar.minimum}Seeking reviews{:else}Not seeking
							reviews{/if}</Status
					></td
				>
				<td
					><Tags
						>{#each volunteer.scholar.sources[sourceID] as expertise}<Tag>{expertise}</Tag
							>{/each}</Tags
					></td
				>
			</tr>
		{/each}
	</Table> -->
{:catch}
	<h1>Unknown Source</h1>
	<Feedback>We couldn't load this source's volunteers.</Feedback>
{/await}
