<script lang="ts">
	import { page } from '$app/state';
	import Feedback from '$lib/components/Feedback.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { reloadOnChanges } from '$lib/data/SupabaseRealtime';
	import { default as ScholarView } from './Scholar.svelte';

	let { data } = $props();

	let {
		commitments,
		venues,
		admins,
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

	// Reload when any related scholar info changes.
	reloadOnChanges('scholar_info_changes', [
		{ table: 'volunteers', filter: `scholarid=eq.${page.params.id}` },
		{ table: 'tokens', filter: `scholar=eq.${page.params.id}` },
		{ table: 'transactions', filter: `from_scholar=eq.${page.params.id}` },
		{ table: 'transactions', filter: `to_scholar=eq.${page.params.id}` },
		{ table: 'assignments', filter: `scholar=eq.${page.params.id}` },
		{ table: 'submissions', filter: `authors=in.(${page.params.id})` },
		{ table: 'venues', filter: `admins=in.(${page.params.id})` },
		{ table: 'currencies', filter: `minters=in.(${page.params.id})` }
	]);
</script>

{#if state}
	<ScholarView
		scholar={state}
		commitments={volunteering}
		{admins}
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
