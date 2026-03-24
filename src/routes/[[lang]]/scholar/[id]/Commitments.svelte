<script lang="ts">
	import type { CurrencyRow } from '$data/types';
	import Feedback from '$lib/components/Feedback.svelte';
	import Table from '$lib/components/Table.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import VenueLink from '$lib/components/VenueLink.svelte';
	import CurrencyLink from '$lib/components/CurrencyLink.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import { ScholarLabel } from '$lib/components/Labels';
	import Text from '$lib/locales/Text.svelte';
	import { getLocaleContext } from '$routes/Contexts';

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

	const locale = getLocaleContext();
</script>

<Subheader icon={ScholarLabel} text={(l) => l.page.scholar.header.volunteering}></Subheader>

{#if admins === null}
	<Feedback text={(l) => l.page.scholar.feedback.commitmentsNotLoaded}></Feedback>
{:else if admins.length === 0 && (minting === null || minting.length === 0) && (commitments === null || commitments.length === 0)}
	<Feedback
		text={(l) =>
			self
				? l.page.scholar.feedback.notVolunteeringFirst
				: l.page.scholar.feedback.notVolunteeringThird}
	/>
{:else}
	<Text
		markdown
		path={(l) =>
			self ? l.page.scholar.feedback.volunteeringFirst : l.page.scholar.feedback.volunteeringThird}
	/>

	<Table>
		{#snippet header()}
			<th>{locale.view.commitments.headers.venue}</th>
			<th>{locale.view.commitments.headers.role}</th>
		{/snippet}

		<!-- Any admin roles? -->
		{#if admins.length > 0}
			{#each admins as admin, index}
				<tr data-testid="admin-{index}">
					<td><VenueLink id={admin.id} name={admin.title} /></td>
					<td><Tag><Text path={(l) => l.shorthand.admin} /></Tag></td>
				</tr>
			{/each}
		{/if}

		<!-- Are they minters for any currencies? -->
		{#each minting ?? [] as currency}
			<tr>
				<td><CurrencyLink {currency} /></td>
				<td><Tag><Text path={(l) => l.shorthand.minter} /></Tag></td>
			</tr>
		{/each}

		<!-- Any volunteering commitments -->
		{#if commitments && commitments.length > 0}
			{#each commitments as commitment, index}
				<tr data-testid="commitment-{index}">
					<td><VenueLink id={commitment.venueid} name={commitment.venue} /></td>
					<td><Tag>{commitment.name}</Tag></td>
				</tr>
			{/each}
		{/if}
	</Table>
{/if}
