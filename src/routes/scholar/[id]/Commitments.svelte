<script lang="ts">
	import type { CurrencyRow } from '$data/types';
	import Feedback from '$lib/components/Feedback.svelte';
	import Table from '$lib/components/Table.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import VenueLink from '$lib/components/VenueLink.svelte';
	import CurrencyLink from '$lib/components/CurrencyLink.svelte';
	import Tip from '$lib/components/Tip.svelte';

	let {
		commitments,
		editing,
		minting
	}: {
		commitments: { id: string; invited: boolean; name: string; venue: string; venueid: string }[];
		editing: { id: string; title: string }[] | null;
		minting: CurrencyRow[] | null;
	} = $props();
</script>

<h2>volunteering</h2>

<Tip>These are commitments you've made to review or manage currencies.</Tip>

{#if editing === null}
	<Feedback>Unable to load editing commitments.</Feedback>
{:else}
	<Table>
		{#snippet header()}
			<th>Venue</th>
			<th>Role</th>
		{/snippet}

		{#if editing}
			{#if editing.length > 0}
				{#each editing as editing}
					<tr>
						<td><VenueLink id={editing.id} name={editing.title} /></td>
						<td><Tag>Editor</Tag></td>
					</tr>
				{/each}
			{/if}
		{/if}
		<!-- Are they minters for any currencies? -->
		{#each minting ?? [] as currency}
			<tr>
				<td><CurrencyLink {currency} /></td>
				<td><Tag>Minter</Tag></td>
			</tr>
		{/each}
		{#if commitments && commitments.length > 0}
			{#each commitments as commitment}
				<tr>
					<td><VenueLink id={commitment.venueid} name={commitment.venue} /></td>
					<td><Tag>{commitment.name}</Tag></td>
				</tr>
			{/each}
		{/if}
	</Table>
{/if}
