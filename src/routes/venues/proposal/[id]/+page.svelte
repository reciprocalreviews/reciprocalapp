<script lang="ts">
	import type { ProposalRow, ScholarRow, SupporterRow } from '$data/types';
	import Page from '$lib/components/Page.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Card from '$lib/components/Card.svelte';
	import Link from '$lib/components/Link.svelte';
	import { getAuth } from '../../../Auth.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Button from '$lib/components/Button.svelte';
	import { addError, isError } from '../../../errors.svelte';
	import { invalidateAll } from '$app/navigation';
	import { getDB } from '$lib/data/Database';
	import Date from '$lib/components/Date.svelte';

	let {
		data
	}: {
		data: {
			proposal: ProposalRow | null;
			supporters:
				| { scholarid: { id: string; name: string[] }; message: string; created: string }[]
				| null;
		};
		scholars: ScholarRow[] | null;
	} = $props();

	const db = getDB();
	const auth = getAuth();

	let uid = $derived(auth.getUserID());
	let message = $state('');

	let proposal = $derived(data.proposal);
	let supporters = $derived(data.supporters);

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
	<Page title={`Proposal - ${proposal.title}`}>
		<h1>{proposal.title}</h1>
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
				{#if uid !== null && !supporters.some((supporter) => supporter.scholarid.id === uid)}
					<form>
						<TextField
							bind:text={message}
							label="Why should the editors adopt Reciprocal Reviews?"
							inline
							placeholder="why"
							valid={(text) => text.length > 0}
						/>
						<Button tip="Submit support" action={support} active={message.length > 0}
							>Add support</Button
						>
					</form>
				{/if}

				{#each supporters.sort((a, b) => b.created.localeCompare(a.created)) as supporter}
					<p class="support">
						<span class="meta"
							><Link to={`/scholar/${supporter.scholarid.id}`}>{supporter.scholarid.name}</Link
							><Date time={supporter.created} /></span
						>
						{supporter.message}
					</p>
				{/each}
			</Card>
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
		align-items: baseline;
		gap: var(--spacing);
	}
	.support {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
	}
</style>
