<script lang="ts">
	import type { ProposalRow, ScholarRow, SupporterRow } from '$data/types';
	import Page from '$lib/components/Page.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Card from '$lib/components/Card.svelte';
	import Link from '$lib/components/Link.svelte';

	let {
		data
	}: {
		data: {
			proposal: ProposalRow | null;
			supporters: { scholarid: { id: string; name: string[] }; message: string }[] | null;
		};
		scholars: ScholarRow[] | null;
	} = $props();

	console.log(data);

	let proposal = $derived(data.proposal);
	let supporters = $derived(data.supporters);
</script>

{#if proposal && supporters}
	<Page title={`Proposal - ${proposal.title}`}>
		<h1>{proposal.title}</h1>
		<p>
			A community member has proposed this venue adopt Reciprocal Reviews. See below for information
			about the proposal.
		</p>
		<Cards>
			<Card header="Editors">
				<p>
					These are the editors the proposers indicated oversee the venue. If they aren't correct,
					you may contact a <Link to="/about">steward</Link> to correct it.
				</p>
				<ul>
					{#each proposal.editors as editor}
						<li><Link to={`mailto:${editor}`}>{editor}</Link></li>
					{/each}
				</ul>
			</Card>
			<Card header="Census">
				<p>
					The reported estimated number of scholars in this community is <strong
						>{proposal.census}</strong
					>. We won't reach out to the editors above until there are at least 20% of the community
					supporting this proposal.
				</p>

				<p>If this estimate is off, contact a <Link to="/about">steward</Link> to correct it.</p>
			</Card>
			<Card header="Support">
				{#each supporters as supporter}
					<p>
						<Link to={`/scholar/${supporter.scholarid.id}`}>{supporter.scholarid.name}</Link>: {supporter.message}
					</p>
				{/each}
			</Card>
		</Cards>
	</Page>
{:else}
	<h1>Oops.</h1>
	<Feedback error>Unknown proposal.</Feedback>
{/if}
