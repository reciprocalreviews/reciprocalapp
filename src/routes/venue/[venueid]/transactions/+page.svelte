<script lang="ts">
	import { type CurrencyID } from '$data/types.js';
	import Card from '$lib/components/Card.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Circle from '$lib/components/Circle.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Gift from '$lib/components/Gift.svelte';
	import { VenueLabel } from '$lib/components/Labels.js';
	import Page from '$lib/components/Page.svelte';
	import Transactions from '$lib/components/Transactions.svelte';
	import { getDB } from '$lib/data/CRUD.js';

	let { data } = $props();
	let { venue, transactions, count, venues, currencies, scholar, tokens } = $derived(data);

	let db = getDB();
</script>

{#if venue && transactions && venues && currencies && scholar && tokens && count}
	<Page icon={VenueLabel} title={venue.title} breadcrumbs={[[`/venue/${venue.id}`, venue.title]]}>
		{#snippet subtitle()}Transactions{/snippet}
		<p>These are all <Circle icon={count}></Circle> transactions on this venue visible to you.</p>

		{#if venue.admins.includes(scholar.id)}
			<Cards>
				<Card group="admins" icon="🎁" header="gift" note="Send tokens to a scholar" full>
					{#if scholar}
						<Gift
							{tokens}
							purpose="Venue gift"
							success="Your tokens were successfully gifted."
							{currencies}
							venues={venues ?? []}
							transfer={(
								currency: CurrencyID,
								kind: 'venue' | 'scholar',
								giftRecipient: string,
								giftAmount: number,
								purpose: string
							) =>
								currency !== null
									? db().transferTokens(
											scholar.id,
											currency,
											venue.id,
											'venueid',
											giftRecipient,
											kind === 'venue' ? 'venueid' : 'emailorcid',
											giftAmount,
											purpose,
											undefined
										)
									: undefined}
						/>
					{/if}
				</Card>
			</Cards>
		{/if}

		<Transactions
			{transactions}
			{count}
			{venues}
			{currencies}
			more={async (page) => db().getVenueTransactions(venue.id, page)}
		/>
	</Page>
{:else if venue === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown venue.</Feedback>
{:else if transactions === null}
	<h1>Oops.</h1>
	<Feedback error>Unable to retrieve transactions transactions.</Feedback>
{:else if venues === null}
	<h1>Oops.</h1>
	<Feedback error>Unable to retrieve venues.</Feedback>
{:else if currencies === null}
	<h1>Oops.</h1>
	<Feedback error>Unable to retrieve currencies.</Feedback>
{:else if scholar === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{:else if tokens === null}
	<h1>Oops.</h1>
	<Feedback error>Unable to retrieve tokens.</Feedback>
{/if}
