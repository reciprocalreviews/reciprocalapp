<script lang="ts">
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { getAuth } from '../../Auth.svelte';
	import Page from '$lib/components/Page.svelte';
	import SourceLink from '$lib/components/VenueLink.svelte';
	import type { PageData } from './$types';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import { handle } from '../../feedback.svelte';
	import { DeleteLabel, MinterLabel, plural, TokenLabel, VenueLabel } from '$lib/components/Labels';
	import Button from '$lib/components/Button.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { validEmail, validORCID } from '$lib/validation';
	import Note from '$lib/components/Note.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import Link from '$lib/components/Link.svelte';
	import Slider from '$lib/components/Slider.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import Dashboard from '$lib/components/Dashboard.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Card from '$lib/components/Card.svelte';
	import type { ScholarID } from '$data/types';
	import Options from '$lib/components/Options.svelte';
	import Subheader from '$lib/components/Subheader.svelte';

	let { data }: { data: PageData } = $props();

	let { currency, venues, admins, count, scholarCount, venueCount } = $derived(data);

	const db = getDB();
	const auth = getAuth();

	let user = $derived(auth.getUserID());
	let isMinter = $derived(currency && user && currency.minters.includes(user));

	let newMinter = $state('');
	let newTokenOwner = $state<string | undefined>(undefined);
	let newTokenCount = $state(1);
	let newTokenConsent = $state(false);
	let newTokenCreating = $state(false);

	function isValidMinter(text: string | ScholarID) {
		if (validEmail(text)) {
			return admins.some((scholar) => scholar.email === text)
				? "Minters can't be admins of a venue that uses this currency."
				: undefined;
		} else if (validORCID(text)) {
			return admins.some((scholar) => scholar.orcid === text)
				? "Minters can't be admins of a venue that uses this currency."
				: undefined;
		} else return 'Must be a valid email or ORCID';
	}
</script>

<Page
	title={currency ? currency.name : 'Oops'}
	breadcrumbs={[]}
	edit={isMinter && currency !== null
		? {
				placeholder: 'Name',
				valid: (text) => (text.length === 0 ? "The name can't be empty" : undefined),
				update: (text) => db().updateCurrencyName(currency.id, text)
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
				edit={(text) => db().updateCurrencyDescription(currency.id, text)}
				note="Currency descriptions are public."
			/>
		{:else}
			<p>{currency.description}</p>
		{/if}

		<Dashboard
			stats={[
				{ icon: TokenLabel, number: count ?? undefined, title: 'tokens', link: `#tokens` },
				{
					icon: MinterLabel,
					number: currency.minters.length,
					title: plural('minter', currency.minters.length),
					link: `#minters`
				},
				{ number: venueCount ?? undefined, title: 'venues', link: `#venues` }
			]}
		/>

		<Subheader icon={TokenLabel} id="tokens">tokens</Subheader>
		<p>
			There are {#if count !== null}<Tokens amount={count}></Tokens>{:else}an unknown number of{/if}
			tokens minted in this currency, owned by <strong>{scholarCount}</strong> scholars and
			<strong>{venueCount}</strong> distinct venues.
		</p>
		<p>
			<Link to="/currency/{currency.id}/transactions">See all transactions</Link> in this currency.
		</p>
		{#if isMinter && venues}
			<Cards>
				<Card
					subheader
					icon={TokenLabel}
					header="mint tokens"
					note="Create new tokens in this currency."
				>
					<form>
						<Feedback
							>Be careful creating new tokens. Too many tokens per scholar will diminish the
							incentive to earn them.</Feedback
						>
						<Options
							label="Which venue should own the new tokens?"
							options={venues.map((venue) => ({
								label: venue.title,
								value: venue.id
							}))}
							value={newTokenOwner}
						/>
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
									(await handle(db().mintTokens(currency.id, newTokenCount, newTokenOwner)))
								) {
									newTokenCount = 0;
									newTokenCreating = false;
									newTokenConsent = false;
								}
							}}>Mint tokens</Button
						>
					</form>
				</Card>
			</Cards>
		{/if}

		<Subheader icon={MinterLabel} id="minters">minters</Subheader>

		<p>
			These scholars are the minters for this currency. They can see and approve all transactions.
		</p>

		<ul>
			{#each currency.minters as minter, index}
				<li data-testid="minter-{index}">
					<ScholarLink id={minter}></ScholarLink>
					{#if isMinter && currency.minters.length > 1}&nbsp;<Button
							tip="Remove yourself as minter"
							active={currency.minters.length > 1}
							action={() =>
								handle(
									db().editCurrencyMinters(
										currency.id,
										currency.minters.filter((m) => m !== minter)
									)
								)}>{DeleteLabel}</Button
						>{/if}
				</li>
			{/each}
		</ul>

		{#if isMinter}
			<Cards>
				<Card
					subheader
					icon={MinterLabel}
					header="add minter"
					note="Allow another scholar to mint tokens."
				>
					<form>
						<TextField
							label="Scholar"
							bind:text={newMinter}
							size={19}
							placeholder="ORCID or email"
							valid={isValidMinter}
						/><Button
							tip="Add minter"
							active={isValidMinter(newMinter) === undefined}
							action={async () => {
								if (
									await handle(db().addCurrencyMinter(currency.id, currency.minters, newMinter))
								) {
									newMinter = '';
								}
							}}>Add minter</Button
						>
					</form>
					<Note>
						Minters can see, approve, and cancel transactions, and most importantly, mint new tokens
						in this currency. They can also propose and improve currency exchanges and mergers.
					</Note>
				</Card>
			</Cards>
		{/if}

		<Subheader icon={VenueLabel} id="venues">venues</Subheader>

		{#if venues}
			<p>These are the venues that use this currency:</p>
			<ul>
				{#each venues as venue, index}
					<li data-testid="venue-{index}">
						<SourceLink id={venue.id} name={venue.title}></SourceLink>
					</li>
				{/each}
			</ul>
		{:else}
			<Feedback error>Unable to load venues.</Feedback>
		{/if}
	{/if}
</Page>
