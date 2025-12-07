<script lang="ts">
	import { ORCIDRegex } from '$lib/data/ORCID';
	import { type Result } from '$lib/data/CRUD';
	import { validEmail, validORCID } from '$lib/validation';
	import { handle } from '../../routes/feedback.svelte';
	import Button from './Button.svelte';
	import Checkbox from './Checkbox.svelte';
	import Slider from './Slider.svelte';
	import TextField from './TextField.svelte';
	import type {
		CurrencyID,
		CurrencyRow,
		ScholarID,
		TokenRow,
		VenueID,
		VenueRow
	} from '$data/types';
	import Feedback from './Feedback.svelte';
	import Options from './Options.svelte';

	let {
		tokens,
		purpose,
		transfer,
		success,
		currencies,
		venues
	}: {
		tokens: TokenRow[] | null;
		purpose: string;
		success: string;
		currencies: CurrencyRow[];
		venues: VenueRow[];
		transfer: (
			currency: CurrencyID,
			kind: 'venue' | 'scholar',
			receipient: VenueID | ScholarID,
			amount: number,
			purpose: string
		) => Promise<Result<any>> | undefined;
	} = $props();

	let currency = $state<undefined | CurrencyID>(undefined);
	let giftRecipient = $state('');
	let giftAmount = $state(1);
	let giftConsent = $state(false);
	let giftPurpose = $state('');

	$effect(() => {
		giftPurpose = purpose;
	});

	let kind = $state<'scholar' | 'venue'>('scholar');
	let venue = $state<undefined | string>(undefined);
</script>

<form>
	{#if tokens === null || tokens.length === 0}
		<Feedback>You don't have any tokens to gift.</Feedback>
	{:else}
		<fieldset>
			<legend>Gift to...</legend>
			<div>
				<input bind:group={kind} type="radio" id="scholar-choice" name="scholar" value="scholar" />
				<label for="scholar-choice">Scholar</label>
			</div>
			<div>
				<input bind:group={kind} type="radio" id="venue-choice" name="venue" value="venue" />
				<label for="venue-choice">Venue</label>
			</div>
		</fieldset>

		{#if kind === 'scholar'}
			<TextField
				bind:text={giftRecipient}
				label="Recipient"
				size={20}
				placeholder="ORCID or email"
				valid={(text) =>
					validEmail(text) || validORCID(text) ? undefined : 'Must be an email or ORCID'}
			/>
		{:else}
			<Options
				bind:value={venue}
				options={venues.map((venue) => ({
					label: venue.title,
					value: venue.id
				}))}
				label="Select a venue"
			/>
		{/if}

		<Options
			bind:value={currency}
			options={currencies.map((currency) => ({
				label: currency.name,
				value: currency.id
			}))}
			label="What currency should be used?"
		/>
		<Slider
			min={1}
			max={tokens?.filter((t) => t.currency === currency).length ?? 20}
			bind:value={giftAmount}
			step={1}
			label="# of tokens to give">{giftAmount}</Slider
		>
		<TextField bind:text={giftPurpose} label="Purpose" size={20} placeholder="Purpose" />
		<Checkbox bind:on={giftConsent}
			>I understand that these tokens can't be transferred back without the recipient's consent.</Checkbox
		>
		<Button
			tip="Transfer tokens"
			active={(currency !== undefined &&
				giftConsent &&
				kind === 'scholar' &&
				(validEmail(giftRecipient) || ORCIDRegex.test(giftRecipient))) ||
				(kind === 'venue' && venue !== undefined)}
			action={async () => {
				if (currency === undefined) return;
				const recipient = kind === 'venue' ? venue : giftRecipient;
				if (recipient === undefined) return;
				const result = transfer(currency, kind, recipient, giftAmount, giftPurpose);
				if (result && (await handle(result, success))) {
					giftAmount = 1;
					giftConsent = false;
					giftRecipient = '';
				}
			}}>Gift tokens</Button
		>
	{/if}
</form>
