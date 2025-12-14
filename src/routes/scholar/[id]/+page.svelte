<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { default as ScholarView } from './Scholar.svelte';

	let { data } = $props();

	let {
		commitments,
		venues,
		editing,
		tokens,
		transactions,
		submissions,
		currencies,
		minting,
		pending,
		reviews,
		approvals
	} = $derived(data);

	let volunteering = $derived(
		commitments
			?.map((c) => {
				return {
					id: c.id,
					invited: c.accepted === 'invited',
					name: c.roles?.name,
					venue: venues?.find((v) => v.id === c.roles?.venueid)?.title,
					venueid: c.roles?.venueid
				};
			})
			.filter(
				(v): v is { id: string; invited: boolean; name: string; venue: string; venueid: string } =>
					v.name !== undefined && v.venue !== undefined && v.venueid !== undefined
			) ?? []
	);

	let db = getDB();

	/** Register a scholar state. */
	let state = $derived(data.scholar ? db().registerScholar(data.scholar) : null);
</script>

{#if state}
	<ScholarView
		scholar={state}
		commitments={volunteering}
		{editing}
		{tokens}
		{transactions}
		{submissions}
		{currencies}
		{minting}
		{pending}
		{venues}
		{reviews}
		{approvals}
	/>
{:else}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{/if}
