<script lang="ts">
	import Page from '$lib/components/Page.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Card from '$lib/components/Card.svelte';
	import Link from '$lib/components/Link.svelte';
	import { getAuth } from '../../../Auth.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Button from '$lib/components/Button.svelte';
	import { addError, handle, isError } from '../../../errors.svelte';
	import { goto, invalidateAll } from '$app/navigation';
	import { getDB } from '$lib/data/Database';
	import Date from '$lib/components/Date.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import { DeleteLabel } from '$lib/components/Labels';
	import Note from '$lib/components/Note.svelte';
	import validEmails from '$lib/components/validEmails';

	let { data } = $props();

	const db = getDB();
	const auth = getAuth();

	let uid = $derived(auth.getUserID());
	let message = $state('');

	let proposal = $derived(data.proposal);
	// Overriding type due to Supabase bug on inferring types for joins: https://github.com/supabase/postgrest-js/pull/558
	let supporters = $derived(
		data.supporters as
			| {
					id: any;
					scholarid: {
						id: any;
						name: any;
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
		const error = await db.addSupporter(uid, proposal.id, message);
		submitting = false;

		if (error && isError(error)) {
			addError(error);
			submitting = false;
		} else {
			message = '';
			invalidateAll();
		}
	}
</script>

{#if proposal && supporters}
	<Page title={proposal.title} subtitle="Proposal">
		<p>
			A community member has proposed this venue adopt Reciprocal Reviews. See below for information
			about the proposal.
		</p>
		<Cards>
			<Card header="Editors">
				<p>
					These are the editors the proposers indicated oversee the venue. If they aren't correct,
					you may contact a <Link to="/about">steward</Link> to correct it.
				</p>
				<ul>
					{#each proposal.editors as editor}
						<li><Link to={`mailto:${editor}`}>{editor}</Link></li>
					{/each}
				</ul>
			</Card>
			<Card header="Census">
				<p>
					The reported estimated number of scholars in this community is <strong
						>{proposal.census}</strong
					>. We won't reach out to the editors above until there are at least 20% of the community
					supporting this proposal.
				</p>

				<p>If this estimate is off, contact a <Link to="/about">steward</Link> to correct it.</p>
			</Card>
			<Card header="Support">
				<!-- Don't allow  -->
				{#if uid !== null}
					{#if !supporters.some((supporter) => supporter.scholarid.id === uid)}
						<form>
							<TextField
								bind:text={message}
								label="support"
								inline
								placeholder="Why should the editors adopt Reciprocal Reviews?"
								valid={(text) => text.length > 0}
							/>
							<Button tip="Submit support" action={support} active={message.length > 0}
								>Add support</Button
							>
						</form>
					{:else}
						<Feedback>You've expressed support. You can edit or delete your support below.</Feedback
						>
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
								><Link to={`/scholar/${scholar.id}`}>{scholar.name}</Link><Date
									time={supporter.created}
								/>
								{#if editable}
									<Button
										tip="Delete support"
										action={() => {
											db.deleteSupport(supporter.id);
											invalidateAll();
											goto('/venues');
										}}>{DeleteLabel}</Button
									>
								{/if}
							</span>
						</p>
						{#if editable}
							<EditableText
								text={supporter.message}
								placeholder="Reasons for support."
								change="Edit your support"
								save="Save your edits."
								valid={(text) => text.length > 0}
								edit={(text) => db.editSupport(supporter.id, text)}
							/>
						{:else}
							<p>
								{supporter.message}
							</p>
						{/if}
					</div>
				{/each}
			</Card>
			{#if data.scholar?.steward}
				<Card header="Admin">
					<EditableText
						label="title"
						text={proposal.title}
						placeholder="Venue title"
						change="Edit the venue title"
						save="Save your edits"
						valid={(text) => text.length > 0}
						edit={(text) => handle(db.editProposalTitle(proposal.id, text))}
					/>
					<EditableText
						label="editors"
						text={proposal.editors.join(', ')}
						placeholder="Venue editors"
						change="Edit the venue editors"
						save="Save the editors"
						valid={validEmails}
						edit={(text) =>
							handle(
								db.editProposalEditors(
									proposal.id,
									text.split(',').map((editor) => editor.trim())
								)
							)}
					/>
					<EditableText
						label="census"
						text={proposal.census}
						placeholder="Venue census"
						change="Edit the venue's census"
						save="Save your edits"
						valid={(text) => !isNaN(parseInt(text))}
						edit={(text) => handle(db.editProposalCensus(proposal.id, parseInt(text)))}
					/>

					<Button
						tip="Delete this proposal"
						warn
						action={async () => {
							if (await handle(db.deleteProposal(proposal.id))) goto('/venues');
						}}>Delete proposal…</Button
					>
					<Note>This cannot be undone.</Note>
				</Card>
			{/if}
		</Cards>
	</Page>
{:else}
	<h1>Oops.</h1>
	<Feedback error>Unknown proposal.</Feedback>
{/if}

<style>
	.meta {
		display: flex;
		flex-direction: row;
		align-items: center;
		gap: var(--spacing);
	}

	.support {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
	}
</style>
