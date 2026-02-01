<script lang="ts">
	import type { CurrencyRow } from '$data/types';
	import Feedback from '$lib/components/Feedback.svelte';
	import Table from '$lib/components/Table.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import VenueLink from '$lib/components/VenueLink.svelte';
	import CurrencyLink from '$lib/components/CurrencyLink.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import { ScholarLabel } from '$lib/components/Labels';

	let {
		commitments,
		admins,
		minting,
		self
	}: {
		commitments: { id: string; invited: boolean; name: string; venue: string; venueid: string }[];
		admins: { id: string; title: string }[] | null;
		minting: CurrencyRow[] | null;
		self: boolean;
	} = $props();
</script>

<Subheader icon={ScholarLabel}>Volunteering</Subheader>

{#if admins === null}
	<Feedback>Unable to load editing commitments.</Feedback>
{:else if admins.length === 0 && (minting === null || minting.length === 0) && (commitments === null || commitments.length === 0)}
	<Feedback>You are not volunteering for any roles yet.</Feedback>
{:else}
	<Tip>
		{#if self}
			These are roles you've volunteered for.
		{:else}
			These are roles this scholar has volunteered for.
		{/if}
	</Tip>

	<Table>
		{#snippet header()}
			<th>Venue</th>
			<th>Role</th>
		{/snippet}

		<!-- Any admin roles? -->
		{#if admins.length > 0}
			{#each admins as admin}
				<tr>
					<td><VenueLink id={admin.id} name={admin.title} /></td>
					<td><Tag>Admin</Tag></td>
				</tr>
			{/each}
		{/if}

		<!-- Are they minters for any currencies? -->
		{#each minting ?? [] as currency}
			<tr>
				<td><CurrencyLink {currency} /></td>
				<td><Tag>Minter</Tag></td>
			</tr>
		{/each}

		<!-- Any volunteering commitments -->
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
