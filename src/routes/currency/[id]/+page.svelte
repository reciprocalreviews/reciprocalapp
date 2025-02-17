<script lang="ts">
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { getAuth } from '../../Auth.svelte';
	import Page from '$lib/components/Page.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Card from '$lib/components/Card.svelte';
	import SourceLink from '$lib/components/VenueLink.svelte';
	import type { PageData } from './$types';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import { handle } from '../../feedback.svelte';
	import { DeleteLabel } from '$lib/components/Labels';
	import Button from '$lib/components/Button.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { validEmail } from '$lib/validation';
	import { ORCIDRegex } from '$lib/data/ORCID';
	import Note from '$lib/components/Note.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import Link from '$lib/components/Link.svelte';
	import Slider from '$lib/components/Slider.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';

	let { data }: { data: PageData } = $props();

	let { currency, venues, count, scholarCount, venueCount } = $derived(data);

	const db = getDB();
	const auth = getAuth();

	let user = $derived(auth.getUserID());
	let isMinter = $derived(currency && user && currency.minters.includes(user));

	let newMinter = $state('');
	let newTokenOwner = $state<string | undefined>(undefined);
	let newTokenCount = $state(1);
	let newTokenConsent = $state(false);
	let newTokenCreating = $state(false);
</script>

<Page
	title={currency ? currency.name : 'Oops'}
	breadcrumbs={[]}
	edit={isMinter && currency !== null
		? {
				placeholder: 'Name',
				valid: (text) => (text.length === 0 ? "The name can't be empty" : undefined),
				update: (text) => db.updateCurrencyName(currency.id, text)
			}
		: undefined}
>
	{#snippet subtitle()}Currency{/snippet}
	{#if currency === null}
		<Feedback error>Unknown currency.</Feedback>
	{:else}
		{#if isMinter}
			<EditableText
				inline={false}
				text={currency.description}
				placeholder="Explain the currency to others."
				edit={(text) => db.updateCurrencyDescription(currency.id, text)}
				note="Currency descriptions are public."
			/>
		{:else}
			<p>{currency.description}</p>
		{/if}
		<Cards>
			<Card icon={currency.minters.length} header="minters" note="Scholars with the power to mint.">
				<p>These scholars are the minters for this currency. They can see all transactions.</p>
				<ul>
					{#each currency.minters as minter}
						<li>
							<ScholarLink id={minter}></ScholarLink>
							{#if isMinter && currency.minters.length > 1}&nbsp;<Button
									tip="Remove yourself as minter"
									active={currency.minters.length > 1}
									action={() =>
										handle(
											db.editCurrencyMinters(
												currency.id,
												currency.minters.filter((m) => m !== minter)
											)
										)}>{DeleteLabel}</Button
								>{/if}
						</li>
					{/each}
				</ul>

				{#if isMinter}
					<form>
						<TextField
							bind:text={newMinter}
							size={19}
							placeholder="ORCID or email"
							valid={(text) =>
								validEmail(text) || ORCIDRegex.test(text)
									? undefined
									: 'Must be a valid email or ORCID'}
						/><Button
							tip="Add minter"
							active={validEmail(newMinter) || ORCIDRegex.test(newMinter)}
							action={async () => {
								if (await handle(db.addCurrencyMinter(currency.id, currency.minters, newMinter))) {
									newMinter = '';
								}
							}}>Add minter</Button
						>
					</form>
					<Note>
						Minters can see, approve, and cancel transactions, and most importantly, mint new tokens
						in this currency. They can also propose and improve currency exchanges and mergers.
					</Note>
				{/if}
			</Card>
			<Card icon={count ?? 0} header="tokens" note="And many transactions...">
				<p>
					There are {#if count !== null}<Tokens amount={count}></Tokens>{:else}an unknown number of{/if}
					tokens minted in this currency, owned by <strong>{scholarCount}</strong> scholars and
					<strong>{venueCount}</strong> distinct venues.
				</p>
				<p>
					<Link to="/currency/{currency.id}/transactions">See all transactions</Link> in this currency.
				</p>
				{#if isMinter && venues}
					<form>
						<h3>Mint tokens</h3>
						<Feedback
							>Be careful creating new tokens. Too many tokens per scholar will diminish the
							incentive to earn them.</Feedback
						>
						<label>
							Which venue should own the new tokens?
							<select bind:value={newTokenOwner}>
								{#each venues as venue}<option value={venue.id}>{venue.title}</option
									>{/each}</select
							>
						</label>
						<Slider
							min={1}
							max={20}
							value={newTokenCount}
							step={1}
							label="Number of new tokens"
							change={(val) => (newTokenCount = val)}>{newTokenCount}</Slider
						>
						<Checkbox bind:on={newTokenConsent}>
							I understand that creating excess tokens will erode this currencies value.</Checkbox
						>

						<Button
							tip="Mint tokens"
							active={!newTokenCreating &&
								newTokenConsent &&
								newTokenCount > 0 &&
								newTokenOwner !== undefined}
							action={async () => {
								newTokenCreating = true;
								if (
									newTokenOwner !== undefined &&
									(await handle(db.mintTokens(currency.id, newTokenCount, newTokenOwner)))
								) {
									newTokenCount = 0;
									newTokenCreating = false;
									newTokenConsent = false;
								}
							}}>Mint tokens</Button
						>
					</form>
				{/if}
			</Card>
			<Card icon={venues?.length ?? 0} header="venues" note="Venues using this currency">
				{#if venues}
					<p>These are the venues that use this currency:</p>
					<ul>
						{#each venues as venue}
							<li><SourceLink id={venue.id} name={venue.title}></SourceLink></li>
						{/each}
					</ul>
				{:else}
					<Feedback error>Unable to load venues.</Feedback>
				{/if}
			</Card>
			<!-- {#if isMinter}
				<Card group="minters" icon="⛭" header="settings" note="Update the name, etc.">
					<EditableText
						text={currency.name}
						label="name"
						placeholder="name"
						edit={async (text) => await db.updateCurrencyName(currency.id, text)}
					/>
				</Card>
			{/if} -->
		</Cards>
	{/if}
</Page>
