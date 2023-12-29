<script lang="ts">
	import { page } from '$app/stores';
	import { getDB } from '$lib/Context';
	import Expertise from '$lib/components/Expertise.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Loading from '$lib/components/Loading.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import SourceLink from '$lib/components/SourceLink.svelte';
	import Table from '$lib/components/Table.svelte';

	const db = getDB();
	let volunteersPromise = db.getSourceVolunteers($page.params.id);
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

	<Table>
		{#each volunteers.sort((a, b) => a.balance - b.balance) as volunteer}
			<tr>
				<td><ScholarLink id={volunteer.scholar} /></td>
				<td
					>{#if volunteer.balance < volunteer.scholar.minimum}Seeking <strong
							>{volunteer.scholar.minimum - volunteer.balance}</strong
						> reviews{:else}Not seeking reviews{/if}</td
				>
				<td><Expertise phrases={volunteer.scholar.expertise} /></td>
			</tr>
		{/each}
	</Table>
{:catch}
	<h1>Unknown Source</h1>
	<Feedback>We couldn't load this source's volunteers.</Feedback>
{/await}
