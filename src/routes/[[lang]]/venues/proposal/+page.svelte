<script lang="ts">
	import { goto } from '$app/navigation';
	import type { CurrencyID } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Form from '$lib/components/Form.svelte';
	import { VenueLabel } from '$lib/components/Labels';
	import Options from '$lib/components/Options.svelte';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Status from '$lib/components/Status.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { getDB } from '$lib/data/CRUD';
	import Text from '$lib/locales/Text.svelte';
	import { isntEmpty, validEmails, validURL } from '$lib/validation';
	import { getAuth } from '$routes/Auth.svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import { addError } from '$routes/feedback.svelte';

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
	const locale = getLocaleContext();

	function validSize(text: string) {
		return parseInt(text) > 0;
	}

	function validMessage(text: string) {
		return text.length > 0;
	}

	function editorsArentMinters() {
		if (currency !== undefined) return true;
		const editorsList = editors.split(',').map((e) => e.trim());
		const mintersList = minters.split(',').map((m) => m.trim());
		return editorsList.filter((value) => mintersList.includes(value)).length === 0;
	}

	async function propose() {
		const uid = auth().getUserID();
		if (
			!isntEmpty(venue) ||
			!validURL(url) ||
			!validEmails(editors, 1) ||
			(currency === undefined && !validEmails(minters, 1)) ||
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
			currency !== undefined ? [] : minters.split(',').map((minter) => minter.trim()),
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

<Page icon={VenueLabel} title={(l) => l.page.proposeVenue.title} breadcrumbs={[]}>
	<Paragraph text={(l) => l.page.proposeVenue.paragraph.reviewedBy} />
	<Paragraph text={(l) => l.page.proposeVenue.paragraph.howToPropose} />

	{#if auth().getUserID()}
		<Form>
			<section class="form-section">
				<p class="section-label"><Text path={(l) => l.page.proposeVenue.section.venueInfo} /></p>
				<TextField
					bind:text={venue}
					strings={(l) => l.page.proposeVenue.field.venueName}
					stretch
					valid={(text) =>
					text.length > 0 ? undefined : (l) => l.page.proposeVenue.field.venueName.invalid}
				/>
				<TextField
					bind:text={url}
					strings={(l) => l.page.proposeVenue.field.url}
					active={!proposing}
					stretch
					valid={(text) =>
						validURL(text) ? undefined : (l) => l.page.proposeVenue.field.url.invalid}
				/>
				<TextField
					bind:text={size}
					strings={(l) => l.page.proposeVenue.field.size}
					active={!proposing}
					stretch
					valid={(text) =>
					validSize(text) ? undefined : (l) => l.page.proposeVenue.field.size.invalid}
				/>
			</section>

			<hr />

			<section class="form-section">
				<p class="section-label"><Text path={(l) => l.page.proposeVenue.section.team} /></p>
				<TextField
					bind:text={editors}
					strings={(l) => l.page.proposeVenue.field.editors}
					active={!proposing}
					stretch
					valid={(text) =>
						!validEmails(text, 1)
						? (l) => l.page.proposeVenue.field.editors.invalid
							: undefined}
				/>
				<Options
					strings={(l) => l.page.proposeVenue.options.currency}
					bind:value={currency}
					stretch
					options={[
						{ label: locale().page.proposeVenue.options.currency.createNew, value: undefined },
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
						stretch
						valid={(text) =>
							!validEmails(text, 1)
							? (l) => l.page.proposeVenue.field.minters.invalid
								: !editorsArentMinters()
									? (l) => l.page.proposeVenue.field.mintersConflict
									: undefined}
					/>
				{/if}
			</section>

			<hr />

			<section class="form-section">
				<p class="section-label"><Text path={(l) => l.page.proposeVenue.section.rationale} /></p>
				<TextField
					bind:text={message}
					strings={(l) => l.page.proposeVenue.field.rationale}
					inline={false}
					active={!proposing}
					stretch
					valid={(text) =>
						validMessage(text)
							? undefined
						: (l) => l.page.proposeVenue.field.rationale.invalid}
				/>
			</section>

			<hr />

			<div class="form-footer">
				<Button
					strings={(l) => l.page.proposeVenue.button.propose}
					action={propose}
					active={!proposing &&
						isntEmpty(venue) &&
						validURL(url) &&
						validEmails(editors, 1) &&
						(currency !== undefined || validEmails(minters, 1)) &&
						validSize(size) &&
						validMessage(message) &&
						editorsArentMinters()}
				/>
			</div>
		</Form>
	{:else}
		<Status good={false} label={(l) => l.page.proposeVenue.status.notLoggedIn} />
	{/if}
</Page>

<style>
	.form-section {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
		width: 100%;
	}

	.section-label {
		font-size: var(--extra-small-font-size);
		font-weight: 600;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--inactive-color);
		margin: 0 0 var(--spacing-half);
	}

	.form-footer {
		display: flex;
		justify-content: flex-end;
		width: 100%;
	}
</style>