<script lang="ts">
	import { ORCIDRegex } from '$lib/data/ORCID';
	import { type Result } from '$lib/data/CRUD';
	import { validEmail } from '$lib/validation';
	import { handle } from '../../routes/feedback.svelte';
	import Button from './Button.svelte';
	import Checkbox from './Checkbox.svelte';
	import Slider from './Slider.svelte';
	import TextField from './TextField.svelte';

	let {
		max,
		purpose,
		transfer,
		success
	}: {
		max: number | null;
		purpose: string;
		success: string;
		transfer: (
			receipient: string,
			amount: number,
			purpose: string
		) => Promise<Result<any>> | undefined;
	} = $props();

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
	<Slider min={1} max={max ?? 20} bind:value={giftAmount} step={1} label="# of tokens to give"
		>{giftAmount}</Slider
	>
	<TextField bind:text={giftPurpose} label="Purpose" size={20} placeholder="Purpose" />
	<Checkbox bind:on={giftConsent}
		>I understand that these tokens can't be transferred back without the recipient's consent.</Checkbox
	>
	<Button
		tip="Transfer tokens"
		active={giftConsent && (validEmail(giftRecipient) || ORCIDRegex.test(giftRecipient))}
		action={async () => {
			const result = transfer(giftRecipient, giftAmount, giftPurpose);
			if (result && (await handle(result, success))) {
				giftAmount = 1;
				giftConsent = false;
				giftRecipient = '';
			}
		}}>Gift tokens</Button
	>
</form>
