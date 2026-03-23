<script lang="ts">
	import { goto } from '$app/navigation';
	import Button from '$lib/components/Button.svelte';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
	import Status from '$lib/components/Status.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { validEmails, isntEmpty, validURL } from '$lib/validation';
	import { getDB } from '$lib/data/CRUD';
	import { getAuth } from '$routes/Auth.svelte';
	import { addError } from '$routes/feedback.svelte';
	import type { CurrencyID } from '$data/types';
	import Options from '$lib/components/Options.svelte';
	import { VenueLabel } from '$lib/components/Labels';

	let { data } = $props();

	let currencies = $derived(data.currencies);

	let venue = $state('');
	let editors = $state('');
	let minters = $state('');
	let currency = $state<undefined | CurrencyID>(undefined);
	let url = $state('');
	let size = $state('');
	let message = $state('');
	let proposing = $state(false);

	const db = getDB();
	const auth = getAuth();

	function validSize(text: string) {
		return parseInt(text) > 0;
	}

	function validMessage(text: string) {
		return text.length > 0;
	}

	function editorsArentMinters() {
		const editorsList = editors.split(',').map((e) => e.trim());
		const mintersList = minters.split(',').map((m) => m.trim());
		return editorsList.filter((value) => mintersList.includes(value)).length === 0;
	}

	async function propose() {
		const uid = auth.getUserID();
		if (
			!isntEmpty(venue) ||
			!validEmails(editors) ||
			!validSize(size) ||
			!validMessage(message) ||
			!editorsArentMinters() ||
			uid === null
		)
			return;

		proposing = true;

		const { data: proposalID, error: proposalError } = await db().proposeVenue(
			uid,
			venue,
			url,
			editors.split(',').map((editor) => editor.trim()),
			currency ?? null,
			minters.split(',').map((minter) => minter.trim()),
			parseInt(size),
			message
		);

		if (proposalError) {
			addError(proposalError);
			proposing = false;
		} else {
			goto(`/venues/proposal/${proposalID}`);
		}
		return;
	}
</script>

<Page icon={VenueLabel} title="Propose a venue" breadcrumbs={[]}>
	<p>
		Venues are currently reviewed and approved by the <Link to="/about#managers">stewards</Link>, to
		ensure that only official editors and conference steering committees are creating venues.
	</p>

	<p>
		To propose a venue, share a few details about the venue, and the stewards will review them. Your
		proposal will appear publicly on the venues page, for others to support.
	</p>

	{#if auth.getUserID()}
		<form>
			<TextField
				bind:text={venue}
				strings={(l) => l.page.proposeVenue.field.venueName}
				valid={(text) =>
					text.length > 0 ? undefined : (l) => l.page.proposeVenue.field.venueName.invalid ?? ''}
			/>
			<TextField
				bind:text={editors}
				strings={(l) => l.page.proposeVenue.field.editors}
				active={!proposing}
				valid={(text) =>
					!validEmails(text, 1)
						? (l) => l.page.proposeVenue.field.editors.invalid ?? ''
						: undefined}
			/>
			<Options
				label="Currency"
				bind:value={currency}
				options={[
					{ label: 'Create a new currency', value: undefined },
					...(currencies ?? []).map((currency) => ({
						label: currency.name,
						value: currency.id
					}))
				]}
			/>
			{#if currency === undefined}
				<TextField
					bind:text={minters}
					strings={(l) => l.page.proposeVenue.field.minters}
					active={!proposing}
					valid={(text) =>
						!validEmails(text, 1)
							? (l) => l.page.proposeVenue.field.minters.invalid ?? ''
							: !editorsArentMinters()
								? (l) => l.page.proposeVenue.field.mintersConflict
								: undefined}
				/>
			{/if}
			<TextField
				bind:text={url}
				strings={(l) => l.page.proposeVenue.field.url}
				active={!proposing}
				valid={(text) =>
					validURL(text) ? undefined : (l) => l.page.proposeVenue.field.url.invalid}
			/>
			<TextField
				bind:text={size}
				strings={(l) => l.page.proposeVenue.field.size}
				active={!proposing}
				valid={(text) =>
					validSize(text) ? undefined : (l) => l.page.proposeVenue.field.size.invalid ?? ''}
			/>
			<TextField
				bind:text={message}
				strings={(l) => l.page.proposeVenue.field.rationale}
				inline={false}
				active={!proposing}
				valid={(text) =>
					validMessage(text) ? undefined : (l) => l.page.proposeVenue.field.rationale.invalid ?? ''}
			/>
			<Button
				strings={(l) => l.page.proposeVenue.button.propose}
				action={propose}
				active={!proposing &&
					isntEmpty(venue) &&
					validEmails(editors, 1) &&
					(currency !== undefined || validEmails(minters, 1)) &&
					validSize(size) &&
					validMessage(message) &&
					editorsArentMinters()}
			/>
		</form>
	{:else}
		<Status good={false}><Link to="/login">Log in</Link> to propose a venue.</Status>
	{/if}
</Page>
