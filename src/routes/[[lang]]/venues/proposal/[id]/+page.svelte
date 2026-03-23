<script lang="ts">
	import Page from '$lib/components/Page.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Card from '$lib/components/Card.svelte';
	import Link from '$lib/components/Link.svelte';
	import { getAuth } from '../../../../Auth.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Button from '$lib/components/Button.svelte';
	import { addError, handle } from '../../../../feedback.svelte';
	import { goto, invalidateAll } from '$app/navigation';
	import { getDB } from '$lib/data/CRUD';
	import Date from '$lib/components/Date.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import { ErrorLabel, VenueLabel } from '$lib/components/Labels';
	import Note from '$lib/components/Note.svelte';
	import { validEmails, validURL } from '$lib/validation';
	import { SettingsLabel } from '$lib/components/Labels';
	import { reloadOnChanges } from '$lib/data/SupabaseRealtime';
	import { page } from '$app/state';

	let { data } = $props();

	const db = getDB();
	const auth = getAuth();

	// Reload when support changes.
	reloadOnChanges('proposal_changes', [
		{ table: 'supporters', filter: `proposalid=eq.${page.params.id}` }
	]);

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
					created_at: string;
			  }[]
			| null
	);

	let submitting = $state(false);
	async function support() {
		if (uid === null || proposal === null) return;
		submitting = true;
		const { error } = await db().addVenueProposalSupporter(uid, proposal.id, message);
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

{#if proposal === null || supporters === null}
	<Page icon={ErrorLabel} title={(l) => l.page.error.title} breadcrumbs={[]}>
		<Feedback error text={(l) => l.page.proposal.feedback.notFound}></Feedback>
	</Page>
{:else}
	<Page icon={VenueLabel} title={proposal.title} breadcrumbs={[]}>
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
				<Card group="steward" icon={SettingsLabel} strings={(l) => l.page.venues.card.settings}>
					<EditableText
						strings={(l) => l.page.venues.field.title}
						text={proposal.title}
						valid={(text) =>
							text.length > 0 ? undefined : (l) => l.page.venues.field.title.invalid}
						edit={(text) => db().editVenueProposalTitle(proposal.id, text)}
					/>
					<EditableText
						strings={(l) => l.page.venues.field.editors}
						text={proposal.editors.join(', ')}
						valid={(text) =>
							validEmails(text) ? undefined : (l) => l.page.venues.field.editors.invalid}
						edit={(text) =>
							db().editVenueProposalEditors(
								proposal.id,
								text.split(',').map((editor) => editor.trim())
							)}
					/>
					<EditableText
						strings={(l) => l.page.venues.field.minters}
						text={proposal.minters.join(', ')}
						valid={(text) =>
							validEmails(text) ? undefined : (l) => l.page.venues.field.minters.invalid}
						edit={(text) =>
							db().editVenueProposalMinters(
								proposal.id,
								text.split(',').map((editor) => editor.trim())
							)}
					/>
					<EditableText
						text={'' + proposal.census}
						strings={(l) => l.page.venues.field.census}
						valid={(text) =>
							!isNaN(parseInt(text)) ? undefined : (l) => l.page.venues.field.census.invalid}
						edit={(text) => db().editVenueProposalCensus(proposal.id, parseInt(text))}
					/>
					<EditableText
						strings={(l) => l.page.venues.field.url}
						text={proposal.url}
						valid={(text) => (validURL(text) ? undefined : (l) => l.page.venues.field.url.invalid)}
						edit={(text) => db().editVenueProposalURL(proposal.id, text)}
					/>

					<Button
						strings={(l) => l.page.proposal.button.deleteProposal}
						action={async () => {
							if (await handle(db().deleteVenueProposal(proposal.id))) goto('/venues');
						}}
					/>
					<Note path={(l) => l.page.proposal.note.delete} />

					<Button
						strings={(l) => l.page.proposal.button.approve}
						action={async () => {
							if (await handle(db().approveVenueProposal(proposal.id))) goto('/venues');
						}}
					/>

					<Note path={(l) => l.page.proposal.note.editors} />
				</Card>
			{/if}
		</Cards>

		{#if uid !== null}
			{#if !approved && !supporters.some((supporter) => supporter.scholarid.id === uid)}
				<form>
					<TextField
						bind:text={message}
						strings={(l) => l.page.proposal.field.support}
						inline
						active={!submitting}
						valid={(text) =>
							text.length > 0 ? undefined : (l) => l.page.proposal.field.support.invalid ?? ''}
					/>
					<Button
						strings={(l) => l.page.proposal.button.submitSupport}
						action={support}
						active={message.length > 0 && !submitting}
					/>
				</form>
			{:else if !approved}
				<Feedback text={(l) => l.page.proposal.feedback.alreadySupported}></Feedback>
			{/if}
		{:else}
			<Feedback text={(l) => l.page.proposal.feedback.logIn}></Feedback>
		{/if}

		{#each supporters.sort((a, b) => b.created_at.localeCompare(a.created_at)) as supporter}
			{@const scholar = supporter.scholarid}
			{@const editable = scholar.id === uid}
			<div class="support">
				<p class="support">
					<span class="meta"
						><Link to={`/scholar/${scholar.id}`}>{scholar.name ? scholar.name : scholar.email}</Link
						><Date time={supporter.created_at} />
						{#if !approved && editable}
							<Button
								strings={(l) => l.page.proposal.button.deleteSupport}
								action={async () => {
									const { error } = await db().deleteVenueProposalSupport(supporter.id);
									if (error) addError(error);
									else {
										invalidateAll();
										goto('/venues');
									}
								}}
							></Button>
						{/if}
					</span>
				</p>
				{#if !approved && editable}
					<EditableText
						strings={(l) => l.page.proposal.field.support}
						text={supporter.message}
						valid={(text) =>
							text.length > 0 ? undefined : (l) => l.page.proposal.field.support.invalid ?? ''}
						edit={(text) => db().editVenueProposalSupport(supporter.id, text)}
					/>
				{:else}
					<p>
						{supporter.message}
					</p>
				{/if}
			</div>
		{/each}
	</Page>
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
