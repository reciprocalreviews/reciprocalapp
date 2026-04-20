<script lang="ts">
	import type { ScholarID } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Card from '$lib/components/Card.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import Dashboard from '$lib/components/Dashboard.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import {
		MinterLabel,
		plural,
		ScholarLabel,
		TokenLabel,
		VenueLabel
	} from '$lib/components/Labels';
	import Note from '$lib/components/Note.svelte';
	import Options from '$lib/components/Options.svelte';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Slider from '$lib/components/Slider.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import SourceLink from '$lib/components/VenueLink.svelte';
	import { getDB } from '$lib/data/CRUD';
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';
	import { validEmail, validORCID } from '$lib/validation';
	import { getAuth } from '$routes/Auth.svelte';
	import { handle } from '$routes/feedback.svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	let { currency, venues, admins, count, scholarCount, venueCount } = $derived(data);

	const db = getDB();
	const auth = getAuth();

	let user = $derived(auth().getUserID());
	let isMinter = $derived(currency && user && currency.minters.includes(user));

	let newMinter = $state('');
	let newTokenOwner = $state<string | undefined>(undefined);
	let newTokenCount = $state(1);
	let newTokenConsent = $state(false);
	let newTokenCreating = $state(false);
	let newTokenPurpose = $state('');

	function isValidMinter(text: string | ScholarID) {
		if (validEmail(text)) {
			return admins.some((scholar) => scholar.email === text)
				? (l: LocaleText) => l.page.currency.field.minter.invalidMinter
				: undefined;
		} else if (validORCID(text)) {
			return admins.some((scholar) => scholar.orcid === text)
				? (l: LocaleText) => l.page.currency.field.minter.invalidMinter
				: undefined;
		} else return (l: LocaleText) => l.page.currency.field.minter.invalidContact;
	}
</script>

<Page
	icon={TokenLabel}
	title={currency ? currency.name : 'Oops'}
	breadcrumbs={[]}
	edit={isMinter && currency !== null
		? {
				placeholder: (l: LocaleText) => l.page.currency.field.name.placeholder,
				valid: (text) =>
					text.length === 0 ? (l: LocaleText) => l.page.currency.field.name.invalid : undefined,
				update: (text) => db().updateCurrencyName(currency.id, text)
			}
		: undefined}
>
	{#snippet subtitle()}<Text path={(l) => l.page.currency.subtitle} />{/snippet}
	{#if currency === null}
		<Feedback error text={(l) => l.page.currency.feedback.notLoaded} />
	{:else}
		{#if isMinter}
			<EditableText
				inline={false}
				text={currency.description}
				strings={(l) => l.page.currency.field.description}
				edit={(text) => db().updateCurrencyDescription(currency.id, text)}
			/>
		{:else}
			<Paragraph text={() => currency.description} />
		{/if}

		<Dashboard
			stats={[
				{ icon: TokenLabel, number: count ?? undefined, title: 'tokens', link: `#tokens` },
				{
					icon: ScholarLabel,
					number: scholarCount ?? undefined,
					title: plural('scholar', scholarCount)
				},
				{
					icon: MinterLabel,
					number: currency.minters.length,
					title: plural('minter', currency.minters.length),
					link: `#minters`
				},
				{ number: venueCount ?? undefined, title: 'venues', link: `#venues` }
			]}
		/>

		<Subheader icon={TokenLabel} id="tokens" text={(l) => l.page.currency.header.tokens} />

		<Paragraph text={(l) => l.page.currency.paragraph.allTokens} inputs={{ id: currency.id }} />

		{#if user && isMinter && venues}
			<Cards>
				<Card subheader icon={TokenLabel} strings={(l) => l.page.currency.card.mint}>
					<Form>
						<Tip><Text path={(l) => l.page.currency.tip.mintWarning} /></Tip>
						<Options
							strings={(l) => l.page.currency.options.tokenOwner}
							options={venues.map((venue) => ({
								label: venue.title,
								value: venue.id
							}))}
							bind:value={newTokenOwner}
						/>
						<Slider
							min={1}
							max={20}
							value={newTokenCount}
							step={1}
							strings={(l) => l.page.currency.slider.newTokenCount}
							change={(val) => (newTokenCount = val)}
						/>
						<TextField
							strings={(l) => l.page.currency.field.mintPurpose}
							bind:text={newTokenPurpose}
							size={40}
							valid={(text) =>
								text.length === 0
									? (l) => l.page.currency.field.mintPurpose.invalid ?? ''
									: undefined}
						/>
						<Checkbox
							bind:on={newTokenConsent}
							label={(l) => l.page.currency.checkbox.mintConsent}
						/>

						<Button
							strings={(l) => l.page.currency.button.mint}
							active={!newTokenCreating &&
								newTokenConsent &&
								newTokenCount > 0 &&
								newTokenOwner !== undefined &&
								newTokenPurpose.length > 0}
							action={async () => {
								newTokenCreating = true;
								if (
									newTokenOwner !== undefined &&
									(await handle(
										db().mintTokens(
											user,
											currency.id,
											newTokenCount,
											newTokenOwner,
											newTokenPurpose
										)
									))
								) {
									newTokenCount = 0;
									newTokenCreating = false;
									newTokenConsent = false;
								}
							}}
						/>
					</Form>
				</Card>
			</Cards>
		{/if}

		<Subheader icon={MinterLabel} id="minters" text={(l) => l.page.currency.header.minters} />

		<Paragraph text={(l) => l.page.currency.paragraph.mintersDescription} />

		<ul>
			{#each currency.minters as minter, index}
				<li data-testid="minter-{index}">
					<ScholarLink id={minter}></ScholarLink>
					{#if isMinter && currency.minters.length > 1}&nbsp;<Button
							strings={(l) => l.page.currency.button.removeMinter}
							active={currency.minters.length > 1}
							action={() =>
								handle(
									db().editCurrencyMinters(
										currency.id,
										currency.minters.filter((m) => m !== minter)
									)
								)}
						/>{/if}
				</li>
			{/each}
		</ul>

		{#if isMinter}
			<Cards>
				<Card subheader icon={MinterLabel} strings={(l) => l.page.currency.card.addMinter}>
					<Form>
						<TextField
							strings={(l) => l.page.currency.field.minter}
							bind:text={newMinter}
							size={19}
							valid={isValidMinter}
						/><Button
							strings={(l) => l.page.currency.button.addMinter}
							active={isValidMinter(newMinter) === undefined}
							action={async () => {
								if (
									await handle(db().addCurrencyMinter(currency.id, currency.minters, newMinter))
								) {
									newMinter = '';
								}
							}}
						/>
					</Form>
					<Note path={(l) => l.page.currency.note.minters} />
				</Card>
			</Cards>
		{/if}

		<Subheader icon={VenueLabel} id="venues" text={(l) => l.page.currency.header.venues} />

		{#if venues}
			<Paragraph text={(l) => l.page.currency.paragraph.venuesDescription} />
			<ul>
				{#each venues as venue, index}
					<li data-testid="venue-{index}">
						<SourceLink id={venue.id} name={venue.title}></SourceLink>
					</li>
				{/each}
			</ul>
		{:else}
			<Feedback error text={(l) => l.page.currency.feedback.notLoaded} />
		{/if}
	{/if}
</Page>
