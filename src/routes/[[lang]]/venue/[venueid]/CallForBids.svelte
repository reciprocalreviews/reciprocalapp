<script lang="ts">
	import type { RoleRow } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { getDB, type CallForBidsStatus } from '$lib/data/CRUD';
	import { noteIsSendable } from '$lib/data/callForBids';
	import { handle } from '$routes/feedback.svelte';

	/** Lets a venue's editor or admin write a short personal note to the volunteers of one
	 * biddable role, asking them to come and bid.
	 *
	 * Bidding only works if volunteers actually come and bid, and every other notice RR sends
	 * fires on something having already happened. Nothing said "we are short of bids this week
	 * and would like you to look", so a program chair's only recourse was to export the
	 * volunteer list and mail it from outside RR, losing the opt-out, the mail log, the
	 * delivery tracking and the data download in one step.
	 *
	 * The note is the only prose anybody writes into RR's mail, and it never becomes a body:
	 * `queue_call_for_bids` passes it as one template argument, and the registry escapes it and
	 * defangs any URL scheme in it at send time.
	 *
	 * An affordance, not authorization — the RPC re-derives the caller's authority over the
	 * venue and refuses anyone else. */
	let {
		role
	}: {
		role: RoleRow;
	} = $props();

	const db = getDB();

	/** Local, so the realtime refetch that `handle()` triggers on every write elsewhere on the
	 * page cannot clobber a half-written message. */
	let note = $state('');

	/** How many people would actually receive this, and when the venue last asked. Both need
	 * privileges the client lacks, so they come from `call_for_bids_status` rather than from
	 * counting the role's volunteers here — that count would include people the send skips. */
	let status = $state<CallForBidsStatus | undefined>(undefined);

	async function loadStatus(roleID: string) {
		const { data } = await db().getCallForBidsStatus(roleID);
		if (data) status = data;
	}

	$effect(() => {
		loadStatus(role.id);
	});

	const sendable = $derived(noteIsSendable(note));
</script>

<Form>
	<Paragraph text={(l) => l.view.roles.paragraph.callForBids} />

	{#if status !== undefined}
		{#if status.eligible === 0}
			<Feedback warning text={(l) => l.view.roles.feedback.callForBidsNobody} />
		{:else}
			<Feedback
				text={(l) => l.view.roles.feedback.callForBidsRecipients}
				inputs={{ count: status.eligible.toString() }}
			/>
		{/if}

		<!-- Plain information, not a warning, and it gates nothing: an editor decides when
		     their community needs asking. It is here so two co-chairs do not unknowingly send
		     the same nudge an hour apart. -->
		{#if status.last_sent !== null}
			<Feedback
				size="small"
				text={(l) => l.view.roles.feedback.callForBidsLast}
				inputs={{
					name: status.last_sender ?? '',
					when: new Date(status.last_sent).toLocaleDateString()
				}}
			/>
		{/if}
	{/if}

	<TextField
		bind:text={note}
		strings={(l) => l.view.roles.field.callForBids}
		testid="call-for-bids-note-{role.name}"
		inline={false}
		stretch
		valid={(t) => (noteIsSendable(t) ? undefined : (l) => l.view.roles.field.callForBids.invalid)}
	></TextField>

	<Button
		strings={(l) => l.view.roles.button.callForBids}
		testid="call-for-bids-send-{role.name}"
		active={sendable && status !== undefined && status.eligible > 0}
		action={async () => {
			if (await handle(db().callForBids(role.id, note))) {
				note = '';
				// Refetched rather than assumed: `last_sent` is now this send, and the eligible
				// count can have moved if somebody opted out while the form sat open.
				await loadStatus(role.id);
			}
		}}
	/>
</Form>
