<script lang="ts">
	import Page from '$lib/components/Page.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Card from '$lib/components/Card.svelte';
	import Link from '$lib/components/Link.svelte';
	import { getAuth } from '../../../Auth.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Button from '$lib/components/Button.svelte';
	import { addError, handle } from '../../../feedback.svelte';
	import { goto, invalidateAll } from '$app/navigation';
	import { getDB } from '$lib/data/CRUD';
	import Date from '$lib/components/Date.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import { DeleteLabel } from '$lib/components/Labels';
	import Note from '$lib/components/Note.svelte';
	import { validEmails, validURLError } from '$lib/validation';

	let { data } = $props();

	const db = getDB();
	const auth = getAuth();

	let uid = $derived(auth.getUserID());
	let message = $state('');

	let proposal = $derived(data.proposal);
	let approved = $derived(proposal && proposal.venue !== null);
	let steward = $derived(data.scholar?.steward === true);

	// Overriding type due to Supabase bug on inferring types for joins: https://github.com/supabase/postgrest-js/pull/558
	let supporters = $derived(
		data.supporters as
			| {
					id: any;
					scholarid: {
						id: string;
						name: string | null;
						email: string;
					};
					message: any;
					created: any;
			  }[]
			| null
	);

	let submitting = $state(false);
	async function support() {
		if (uid === null || proposal === null) return;
		submitting = true;
		const { error } = await db.addSupporter(uid, proposal.id, message);
		submitting = false;

		if (error) {
			addError(error);
			submitting = false;
		} else {
			message = '';
			invalidateAll();
		}
	}
</script>

{#if proposal && supporters}
	<Page title={proposal.title} breadcrumbs={[['/venues', 'Venues']]}>
		{#snippet subtitle()}
			{#if approved}
				Approved
			{:else}
				Proposal
			{/if}
		{/snippet}
		{#if approved}
			<p>This proposal was approved. See the <Link to="/venue/{proposal.venue}">venue</Link>.</p>
		{:else}
			<p>
				A community member has proposed <Link to={proposal.url}>{proposal.title}</Link> adopt Reciprocal
				Reviews. See below for information about the proposal.
			</p>

			<p>
				The reported estimated number of scholars in this community is <strong
					>{proposal.census}</strong
				>. We won't reach out to the editors above until there are at least 20% of the community
				supporting this proposal. If this estimate is off, contact a <Link to="/about">steward</Link
				> to correct it.
			</p>

			<p>
				These are the editors the proposers indicated oversee the venue. If they aren't correct, you
				may contact a <Link to="/about">steward</Link> to correct it.
			</p>
			<ul>
				{#each proposal.editors as editor}
					<li><Link to={`mailto:${editor}`}>{editor}</Link></li>
				{/each}
			</ul>
		{/if}
		<Cards>
			{#if steward && !approved}
				<Card group="stewards" icon="⛭" header="settings" note="Title, editors, url, etc.">
					<EditableText
						label="title"
						text={proposal.title}
						placeholder="Venue title"
						valid={(text) => (text.length > 0 ? undefined : 'Include a title')}
						edit={(text) => db.editProposalTitle(proposal.id, text)}
					/>
					<EditableText
						label="editors"
						text={proposal.editors.join(', ')}
						placeholder="Venue editors"
						valid={(text) =>
							validEmails(text) ? undefined : 'Must be a list of comma separated email addresses.'}
						edit={(text) =>
							db.editProposalEditors(
								proposal.id,
								text.split(',').map((editor) => editor.trim())
							)}
					/>
					<EditableText
						label="census"
						text={'' + proposal.census}
						placeholder="Venue census"
						valid={(text) => (!isNaN(parseInt(text)) ? undefined : 'Must be a whole number')}
						edit={(text) => db.editProposalCensus(proposal.id, parseInt(text))}
					/>
					<EditableText
						label="URL"
						text={proposal.url}
						placeholder="https://"
						valid={validURLError}
						edit={(text) => db.editProposalURL(proposal.id, text)}
					/>

					<Button
						tip="Delete this proposal"
						warn="Delete this proposal forever?"
						action={async () => {
							if (await handle(db.deleteProposal(proposal.id))) goto('/venues');
						}}>Delete proposal…</Button
					>
					<Note>This cannot be undone.</Note>

					<Button
						tip="Approve this proposal"
						warn="Approve and create this venue?"
						action={async () => {
							if (await handle(db.approveProposal(proposal.id))) goto('/venues');
						}}>Approve proposal…</Button
					>
					<Note
						>After approving a proposal, <strong>{proposal.editors.join(',')}</strong>
						above will become the editors of the venue.</Note
					>
				</Card>
			{/if}
		</Cards>

		{#if uid !== null}
			{#if !approved && !supporters.some((supporter) => supporter.scholarid.id === uid)}
				<form>
					<TextField
						bind:text={message}
						label="support"
						inline
						placeholder="Why should the editors adopt Reciprocal Reviews?"
						active={!submitting}
						valid={(text) => (text.length > 0 ? undefined : 'Must include a rationale')}
					/>
					<Button tip="Submit support" action={support} active={message.length > 0 && !submitting}
						>Add support</Button
					>
				</form>
			{:else if !approved}
				<Feedback>You've expressed support. You can edit or delete your support below.</Feedback>
			{/if}
		{:else}
			<Feedback>Log in to express support.</Feedback>
		{/if}

		{#each supporters.sort((a, b) => b.created.localeCompare(a.created)) as supporter}
			{@const scholar = supporter.scholarid}
			{@const editable = scholar.id === uid}
			<div class="support">
				<p class="support">
					<span class="meta"
						><Link to={`/scholar/${scholar.id}`}>{scholar.name ? scholar.name : scholar.email}</Link
						><Date time={supporter.created} />
						{#if !approved && editable}
							<Button
								tip="Delete support"
								action={async () => {
									const { error } = await db.deleteSupport(supporter.id);
									if (error) addError(error);
									else {
										invalidateAll();
										goto('/venues');
									}
								}}>{DeleteLabel}</Button
							>
						{/if}
					</span>
				</p>
				{#if !approved && editable}
					<EditableText
						text={supporter.message}
						placeholder="Reasons for support."
						valid={(text) => (text.length > 0 ? undefined : 'Include a message')}
						edit={(text) => db.editSupport(supporter.id, text)}
					/>
				{:else}
					<p>
						{supporter.message}
					</p>
				{/if}
			</div>
		{/each}
	</Page>
{:else}
	<h1>Oops.</h1>
	<Feedback error>Unknown proposal.</Feedback>
{/if}

<style>
	.meta {
		display: flex;
		flex-direction: row;
		align-items: baseline;
		gap: var(--spacing);
	}

	.support {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
	}
</style>
