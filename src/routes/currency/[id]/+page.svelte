<script lang="ts">
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { getAuth } from '../../Auth.svelte';
	import Page from '$lib/components/Page.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Card from '$lib/components/Card.svelte';
	import SourceLink from '$lib/components/SourceLink.svelte';
	import type { PageData } from './$types';
	import ScholarLink from '$lib/components/ScholarLink.svelte';

	let { data }: { data: PageData } = $props();

	let { currency, venues } = $derived(data);

	const db = getDB();
	const auth = getAuth();

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
						<li><ScholarLink id={minter}></ScholarLink></li>
					{/each}
				</ul></Card
			>
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
