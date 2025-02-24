<script lang="ts">
	import { ORCIDRegex } from '$lib/data/ORCID';
	import { type Result } from '$lib/data/CRUD';
	import { validEmail } from '$lib/validation';
	import { handle } from '../../routes/feedback.svelte';
	import Button from './Button.svelte';
	import Checkbox from './Checkbox.svelte';
	import Slider from './Slider.svelte';
	import TextField from './TextField.svelte';
	import type { CurrencyID, CurrencyRow, TokenRow } from '$data/types';

	let {
		tokens,
		purpose,
		transfer,
		success,
		currencies
	}: {
		tokens: TokenRow[] | null;
		purpose: string;
		success: string;
		currencies: CurrencyRow[];
		transfer: (
			currency: CurrencyID,
			receipient: string,
			amount: number,
			purpose: string
		) => Promise<Result<any>> | undefined;
	} = $props();

	let currency = $state<undefined | CurrencyID>(undefined);
	let giftRecipient = $state('');
	let giftAmount = $state(1);
	let giftConsent = $state(false);
	let giftPurpose = $state(purpose);
</script>

<form>
	<h3>Gift tokens</h3>
	<TextField
		bind:text={giftRecipient}
		label="Recipient"
		size={20}
		placeholder="ORCID or email"
		valid={(text) =>
			validEmail(text) || ORCIDRegex.test(text) ? undefined : 'Must be an email or ORCID'}
	/>
	<label>
		What currency should be used?
		<select bind:value={currency}>
			{#each currencies as currency}<option value={currency.id}>{currency.name}</option
				>{/each}</select
		>
	</label>
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
		active={currency !== undefined &&
			giftConsent &&
			(validEmail(giftRecipient) || ORCIDRegex.test(giftRecipient))}
		action={async () => {
			if (currency === undefined) return;
			const result = transfer(currency, giftRecipient, giftAmount, giftPurpose);
			if (result && (await handle(result, success))) {
				giftAmount = 1;
				giftConsent = false;
				giftRecipient = '';
			}
		}}>Gift tokens</Button
	>
</form>
