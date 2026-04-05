<script lang="ts">
	import { type CurrencyID } from '$data/types.js';
	import Card from '$lib/components/Card.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Gift from '$lib/components/Gift.svelte';
	import { ErrorLabel, VenueLabel } from '$lib/components/Labels.js';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Transactions from '$lib/components/Transactions.svelte';
	import { getDB } from '$lib/data/CRUD.js';
	import Text from '$lib/locales/Text.svelte';
	import { getLocaleContext } from '$routes/Contexts.js';

	let { data } = $props();
	let { venue, transactions, count, venues, currencies, scholar, tokens } = $derived(data);

	let db = getDB();
	let locale = getLocaleContext();
</script>

{#if venue && transactions && venues && currencies && scholar && tokens && count !== null}
	<Page icon={VenueLabel} title={venue.title} breadcrumbs={[[`/venue/${venue.id}`, venue.title]]}>
		{#snippet subtitle()}<Text path={(l) => l.page.venueTransactions.subtitle} />{/snippet}

		<Paragraph
			text={(l) => l.page.venueTransactions.paragraph.count}
			inputs={{ count: count.toString() }}
		/>

		{#if venue.admins.includes(scholar.id)}
			<Cards>
				<Card group="admin" icon="🎁" strings={(l) => l.page.venue.card.gift} full>
					{#if scholar}
						<Gift
							{tokens}
							purpose={locale().page.venue.card.gift.purpose}
							success={locale().page.venue.card.gift.success}
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
			isDebit={(transaction) => transaction.from_venue === venue.id}
			testid="venue-transaction"
		/>
	</Page>
{:else}
	<Page icon={ErrorLabel} title={(l) => l.page.error.title} breadcrumbs={[]}>
		<Feedback error text={(l) => l.page.venueTransactions.feedback.transactionsNotLoaded}
		></Feedback>
	</Page>
{/if}
