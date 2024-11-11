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
	import { handle } from '../../errors.svelte';
	import { DeleteLabel } from '$lib/components/Labels';
	import Button from '$lib/components/Button.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { validEmail } from '$lib/validation';
	import { ORCIDRegex } from '$data/ORCID';
	import Note from '$lib/components/Note.svelte';

	let { data }: { data: PageData } = $props();

	let { currency, venues } = $derived(data);

	const db = getDB();
	const auth = getAuth();

	let user = $derived(auth.getUserID());
	let isMinter = $derived(currency && user && currency.minters.includes(user));

	let newMinter = $state('');

	// Editable if the user is the scholar being viewed.
	let uid = $derived(auth.getUserID());
	let editable = $derived(currency !== null && uid !== null && currency.minters.includes(uid));
</script>

<Page title={currency ? currency.name : 'Oops'} subtitle="currency">
	{#if currency === null}
		<Feedback error>Unknown currency.</Feedback>
	{:else}
		{#if editable}
			<EditableText
				inline={false}
				text={currency.description}
				label="status"
				placeholder="Explain the currency to others."
				edit={(text) => db.updateCurrencyDescription(currency.id, text)}
				note="Currency descriptions are public."
			/>
		{:else}
			<p>{currency.description}</p>
		{/if}
		<Cards>
			<Card header="Minters">
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
							valid={(text) => validEmail(text) || ORCIDRegex.test(text)}
						/><Button
							tip="Add minter"
							active={validEmail(newMinter) || ORCIDRegex.test(newMinter)}
							action={async () => {
								if (await handle(db.addCurrencyMinter(currency.id, currency.minters, newMinter)))
									newMinter = '';
							}}>Add minter</Button
						>
					</form>
					<Note>
						Minters can see, approve, and cancel transactions, and most importantly, mint new tokens
						in this currency. They can also propose and improve currency exchanges and mergers.
					</Note>
				{/if}
			</Card>
			<Card header="Venues">
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
			{#if editable}
				<Card header="Settings">
					{#if editable}<EditableText
							text={currency.name}
							label="name"
							placeholder="name"
							edit={async (text) => await db.updateCurrencyName(currency.id, text)}
						/>{:else}{currency.name}{/if}
				</Card>
			{/if}
		</Cards>
	{/if}
</Page>
