<script lang="ts">
	import type { ScholarID, TransactionRow } from '$data/types';
	import Button from './Button.svelte';
	import Dialog from './Dialog.svelte';
	import Paragraph from './Paragraph.svelte';
	import TextField from './TextField.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { handle } from '../../routes/feedback.svelte';

	let {
		transaction,
		index,
		userid,
		testid
	}: {
		transaction: TransactionRow;
		index: number;
		userid: ScholarID;
		testid: string;
	} = $props();

	const db = getDB();

	let showDecline = $state(false);
	let declineReason = $state('');
</script>

<div class="column">
	<!-- If the authenticated scholar is a minter of the given currency, or the giver, then show an approve button -->
	<Button
		strings={(l) => l.view.transactions.button.approve}
		testid={testid + '-' + index + '-approve'}
		action={() => handle(db().approveTransaction(userid, transaction.id))}
	/>
	<Button
		strings={(l) => l.view.transactions.button.declineInitiate}
		testid={testid + '-' + index + '-decline-initiate'}
		active={!showDecline}
		action={() => (showDecline = true)}
	/>
	<Dialog bind:show={showDecline}>
		<Paragraph text={(l) => l.view.transactions.paragraph.declineReason} />
		<TextField
			strings={(l) => l.view.transactions.field.declineReason}
			testid={testid + '-' + index + '-decline-reason'}
			bind:text={declineReason}
		/>
		<Button
			strings={(l) => l.view.transactions.button.declineConfirm}
			testid={testid + '-' + index + '-decline-confirm'}
			active={declineReason.length > 0}
			action={async () => {
				await handle(db().declineTransaction(userid, transaction.id, declineReason));
				showDecline = false;
			}}
		/>
	</Dialog>
</div>

<style>
	.column {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
	}
</style>
