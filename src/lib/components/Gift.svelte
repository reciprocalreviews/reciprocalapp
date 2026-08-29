<script lang="ts">
	import type { CurrencyID, CurrencyRow, ScholarID, VenueID, VenueRow } from '$data/types';
	import { type Result } from '$lib/data/CRUD';
	import { ORCIDRegex } from '$lib/data/ORCID';
	import { validEmail, validORCID } from '$lib/validation';
	import { getLocaleContext } from '$routes/Contexts';
	import { handle } from '../../routes/feedback.svelte';
	import Button from './Button.svelte';
	import Checkbox from './Checkbox.svelte';
	import Feedback from './Feedback.svelte';
	import Form from './Form.svelte';
	import Options from './Options.svelte';
	import Radio from './Radio.svelte';
	import Slider from './Slider.svelte';
	import TextField from './TextField.svelte';

	let {
		balances,
		purpose,
		transfer,
		success,
		currencies,
		venues
	}: {
		/** How many tokens the giver holds, keyed by currency id. A map rather than
		 * the token rows: this only ever needed a count per currency, and the array it
		 * used to filter was the giver's whole token table — capped at `max_rows`, so
		 * a large holder's slider silently topped out at 1000. */
		balances: Record<CurrencyID, number> | null;
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

	const locale = getLocaleContext();

	let total = $derived(
		balances === null ? 0 : Object.values(balances).reduce((sum, n) => sum + n, 0)
	);
</script>

<Form>
	<!-- `null` is "could not be read", not "holds none" — under the private-balance
	rule a failed read is a real possibility, and telling someone they have no
	tokens when they have plenty is worse than saying nothing. Both render the same
	notice for now; the distinction is kept so the slider below cannot silently
	offer a bound drawn from a balance nobody actually read. -->
	{#if balances === null || total === 0}
		<Feedback text={(l) => l.view.gift.noTokens}></Feedback>
	{:else}
		<fieldset>
			<legend>{locale().view.gift.fieldset.legend}</legend>
			<Radio bind:group={kind} value="scholar" label={(l) => l.view.gift.fieldset.scholar} />
			<Radio bind:group={kind} value="venue" label={(l) => l.view.gift.fieldset.venue} />
		</fieldset>

		{#if kind === 'scholar'}
			<TextField
				bind:text={giftRecipient}
				strings={(l) => l.view.gift.field.recipient}
				size={20}
				valid={(text) =>
					validEmail(text) || validORCID(text)
						? undefined
						: (l) => l.view.gift.field.recipient.invalid}
				testid="gift-recipient"
			/>
		{:else}
			<Options
				bind:value={venue}
				options={venues.map((venue) => ({
					label: venue.title,
					value: venue.id
				}))}
				strings={(l) => l.view.gift.options.venue}
			/>
		{/if}

		<Options
			bind:value={currency}
			options={currencies.map((currency) => ({
				label: currency.name,
				value: currency.id
			}))}
			strings={(l) => l.view.gift.options.currency}
		/>
		<Slider
			min={1}
			max={(currency === undefined ? undefined : balances?.[currency]) ?? 0}
			bind:value={giftAmount}
			step={1}
			strings={(l) => l.view.gift.slider.tokenAmount}
			testid="gift-amount"
		/>
		<TextField
			bind:text={giftPurpose}
			strings={(l) => l.view.gift.field.purpose}
			size={20}
			testid="gift-purpose"
		/>
		<Checkbox
			bind:on={giftConsent}
			label={(l) => l.view.gift.checkbox.consent}
			testid="gift-consent"
		/>
		<Button
			strings={(l) => l.view.gift.button.giftTokens}
			testid="gift-submit"
			active={currency !== undefined &&
				giftConsent &&
				((kind === 'scholar' && (validEmail(giftRecipient) || ORCIDRegex.test(giftRecipient))) ||
					(kind === 'venue' && venue !== undefined))}
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
			}}
		/>
	{/if}
</Form>
