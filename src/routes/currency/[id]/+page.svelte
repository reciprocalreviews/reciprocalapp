<script lang="ts">
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { getDB } from '$lib/data/CRUD';
	import type { CurrencyRow } from '../../../data/types';
	import { getAuth } from '../../Auth.svelte';
	import Page from '$lib/components/Page.svelte';

	let { data }: { data: { currency: CurrencyRow | null } } = $props();

	let currency = $derived(data.currency);

	const db = getDB();
	const auth = getAuth();

	// Editable if the user is the scholar being viewed.
	let uid = $derived(auth.getUserID());
	let editable = $derived(currency !== null && uid !== null && currency.minters.includes(uid));
</script>

<Page title="Currency">
	{#if currency === null}
		<h1>Oops.</h1>
		<Feedback error>Unknown currency.</Feedback>
	{:else}
		<h1>
			{#if editable}<EditableText
					text={currency.name}
					placeholder="name"
					change="Change currency name"
					save="Save currency name"
					edit={async (text) => await db.updateCurrencyName(currency.id, text)}
				/>{:else}{currency.name}{/if}
		</h1>

		{#if editable}
			<EditableText
				inline={false}
				text={currency.description}
				label="status"
				placeholder="Explain the currency to others."
				change="Edit description"
				save="Save description"
				edit={(text) => db.updateCurrencyDescription(currency.id, text)}
				note="Currency descriptions are public."
			/>
		{:else}
			<p>{currency.description}</p>
		{/if}
	{/if}
</Page>
