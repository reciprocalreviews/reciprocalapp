<script lang="ts">
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Link from '$lib/components/Link.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import { getDB } from '$lib/data/CRUD';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Page from '$lib/components/Page.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Card from '$lib/components/Card.svelte';
	import { DeleteLabel } from '$lib/components/Labels';
	import { validInteger, validURLError } from '$lib/validation';
	import { handle } from '../../feedback.svelte';
	import Roles from './Roles.svelte';
	import type { PageData } from './$types';
	import Gift from '$lib/components/Gift.svelte';
	import { type CurrencyID } from '$data/types';

	let { data }: { data: PageData } = $props();
	const { venue, currency, scholar, roles, volunteers, tokens, transactionCount, submissionCount } =
		$derived(data);

	const db = getDB();
	let editor = $derived(scholar && venue && venue.editors.includes(scholar.id));
</script>

{#if venue === null}
	<Page title="Unknown venue" breadcrumbs={[]}>
		<p>Unable to find this venue.</p>
	</Page>
{:else}
	<Page
		title={venue.title}
		breadcrumbs={[[`/venues`, 'Venues']]}
		edit={editor
			? {
					placeholder: 'Title',
					valid: (text) => (text.length > 0 ? undefined : 'Must include a title'),
					update: (text) => db.editVenueTitle(venue.id, text)
				}
			: undefined}
	>
		{#snippet subtitle()}Venue{/snippet}
		{#snippet details()}<Link to={venue.url}>{venue.url}</Link>{/snippet}

		<!-- Show the description -->
		{#if editor}
			<EditableText
				text={venue.description}
				placeholder="Venue description."
				inline={false}
				edit={(text) => db.editVenueDescription(venue.id, text)}
			/>
		{:else}
			<p>
				{#if venue.description.length === 0}<em>No description.</em>{:else}{venue.description}{/if}
			</p>
		{/if}

		{#each venue.editors as editorID, index}
			<p>
				This venue is edited by
				<ScholarLink id={editorID} />{#if editor && venue.editors.length > 1}
					&nbsp;<Button
						tip="Remove editor"
						active={venue.editors.length > 1}
						warn="Are you sure you want to remove this editor?"
						action={() =>
							handle(
								db.editVenueEditors(
									venue.id,
									venue.editors.filter((ed) => ed !== editorID)
								)
							)}>{DeleteLabel}</Button
					>{/if}
				{#if index < venue.editors.length - 1},{/if}
				.
			</p>
		{/each}

		<h2>Costs</h2>

		<!-- Key details about costs. -->
		<p>
			{#if currency}
				This venue uses the <Link background to="/currency/{venue.currency}">★ {currency.name}</Link
				>
				currency.
			{:else}
				<Feedback error>Unable to load this venue's currency.</Feedback>
			{/if}
			New volunteers receive <Tokens amount={venue.welcome_amount}></Tokens> when they volunteer to review.
			New submissions cost <Tokens amount={venue.submission_cost}></Tokens>.
		</p>

		<p>
			See the <Link to="/venue/{venue.id}/submissions">{submissionCount ?? 'all'} submissions</Link>
			in this venue.
		</p>

		<h2>Volunteer</h2>

		{#if roles}
			<Roles {venue} scholar={scholar?.id} {roles} {volunteers} editor={editor === true} />
		{:else}
			<Feedback error>Couldn't load venue's roles.</Feedback>
		{/if}

		{#if editor}
			<h2>Tokens</h2>
			<Cards>
				<Card
					expand
					group="editors"
					icon={tokens === null ? '?' : tokens.length}
					header="balance"
					note="balance and gifts"
				>
					<p>
						This venue currently has {#if tokens !== null}<Tokens amount={tokens.length}
							></Tokens>{:else}an unknown number of{/if} tokens and is involved in {#if transactionCount !== null}<strong
								>{transactionCount}</strong
							>{:else}an unknown number of{/if} transactions.
						<Link to="/venue/{venue.id}/transactions">See all transactions</Link>.
					</p>
				</Card>
				<Card group="editors" icon="🎁" header="gift" note="Send tokens to a scholar">
					{#if scholar && currency !== null}
						<Gift
							{tokens}
							purpose="Venue gift to scholar"
							success="Your tokens were successfully gifted."
							currencies={[currency]}
							transfer={(
								currency: CurrencyID,
								giftRecipient: string,
								giftAmount: number,
								purpose: string
							) =>
								currency !== null
									? db.transferTokens(
											scholar.id,
											currency,
											venue.id,
											'venueid',
											giftRecipient,
											'emailorcid',
											giftAmount,
											purpose,
											undefined
										)
									: undefined}
						/>
					{/if}
				</Card>
				<Card group="editors" icon="⛭" header="settings" note="Update title, url, costs, etc.">
					<EditableText
						text={venue.url}
						label="URL"
						placeholder="https://..."
						valid={validURLError}
						edit={(text) => db.editVenueURL(venue.id, text)}
					/>
					<EditableText
						text={venue.welcome_amount.toString()}
						label="Welcome tokens"
						placeholder="e.g., 40"
						valid={(text) => (validInteger(text) ? undefined : 'Must be a whole number')}
						edit={(text) => db.editVenueWelcomeAmount(venue.id, parseInt(text))}
					/>
					<EditableText
						text={venue.submission_cost.toString()}
						label="Submission cost"
						placeholder="e.g., 40"
						valid={(text) => (validInteger(text) ? undefined : 'Must be a whole number')}
						edit={(text) => db.editVenueSubmissionCost(venue.id, parseInt(text))}
					/>
				</Card>
			</Cards>
		{/if}
	</Page>
{/if}
