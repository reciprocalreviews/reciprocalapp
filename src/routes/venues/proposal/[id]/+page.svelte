<script lang="ts">
	import type { ProposalRow } from '../../../../data/types';
	import Page from '$lib/components/Page.svelte';
	import Feedback from '$lib/components/Feedback.svelte';

	let { data }: { data: { proposal: ProposalRow | null } } = $props();

	let proposal = data.proposal;
</script>

{#if proposal}
	<Page title={`Proposal - ${proposal.title}`}>
		<h1>{proposal.title}</h1>
		<p>Editors: {proposal.emails}</p>
		<p>Size: {proposal.census}</p>
	</Page>
{:else}
	<h1>Oops.</h1>
	<Feedback error>Unknown proposal.</Feedback>
{/if}
