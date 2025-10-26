<script lang="ts">
	import type { CurrencyRow } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { EmptyLabel } from '$lib/components/Labels';
	import Table from '$lib/components/Table.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import VenueLink from '$lib/components/VenueLink.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { handle } from '../../feedback.svelte';
	import CurrencyLink from '$lib/components/CurrencyLink.svelte';

	let {
		commitments,
		editing,
		minting
	}: {
		commitments: { id: string; invited: boolean; name: string; venue: string; venueid: string }[];
		editing: { id: string; title: string }[] | null;
		minting: CurrencyRow[] | null;
	} = $props();

	const db = getDB();
</script>

<!-- Find all invitations -->
{#each commitments.filter((v) => v.invited) as invite}
	<Feedback>
		The editor has invited you to the <strong>{invite.name ?? EmptyLabel}</strong>
		role for <VenueLink id={invite.venueid} name={invite.venue} />. Would you like to
		<Button
			tip="accept this invitation"
			action={() => handle(db.acceptRoleInvite(invite.id, 'accepted'))}>Accept</Button
		>
		<Button
			tip="decline this invitation"
			action={() => handle(db.acceptRoleInvite(invite.id, 'declined'))}>Decline</Button
		>?
	</Feedback>
{/each}

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
