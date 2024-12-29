<script lang="ts">
	import { getDB } from '$lib/data/CRUD';
	import Link from '$lib/components/Link.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import { getAuth } from '../../Auth.svelte';
	import type Scholar from '$lib/data/Scholar.svelte';
	import Status from '$lib/components/Status.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Card from '$lib/components/Card.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import SourceLink from '$lib/components/VenueLink.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import Gift from '$lib/components/Gift.svelte';
	import Bubble from '$lib/components/Bubble.svelte';
	import Note from '$lib/components/Note.svelte';
	import Page from '$lib/components/Page.svelte';

	let {
		scholar,
		commitments,
		editing,
		tokens,
		transactions
	}: {
		scholar: Scholar;
		commitments: { name: string; venue: string; venueid: string }[];
		editing: { id: string; title: string }[] | null;
		tokens: number | null;
		transactions: number | null;
	} = $props();

	const db = getDB();
	const auth = getAuth();

	// Editable if the user is the scholar being viewed.
	let editable = $derived(auth.getUserID() === scholar.getID());
</script>

<Page title={scholar.getName() ?? 'anonymous'}>
	{#snippet subtitle()}
		Scholar | <Link to="https://orcid.org/{scholar.getORCID()}">ORCID</Link> | <Link
			to="mailto:{scholar.getEmail()}">{scholar.getEmail()}</Link
		>
	{/snippet}

	<h2>Status</h2>
	<Status good={scholar.isAvailable()}>{scholar.isAvailable() ? 'Available' : 'Unavailable'}</Status
	>

	{#if editable}
		<Checkbox
			on={scholar.isAvailable()}
			change={(on) => db.updateScholarAvailability(scholar.getID(), on)}
			>I am available to review.</Checkbox
		>
	{/if}

	{#if editable}
		<EditableText
			inline={false}
			text={scholar.getStatus()}
			label="status"
			placeholder="Explain your current reviewing status to others."
			edit={(text) => db.updateScholarStatus(scholar.getID(), text)}
			note="Your status is public and will be shown here."
		/>
	{:else}
		<p>{scholar.getStatus()}</p>
	{/if}

	<Cards>
		<Card
			icon={commitments.length + (editing?.length ?? 0)}
			header="commitments"
			description="venues volunteered for"
		>
			{#if commitments}
				{#if commitments.length > 0}
					<ul>
						{#each commitments as commitment}
							<li>
								<SourceLink id={commitment.venueid} name={commitment.venue} />
								<Tag>{commitment.name}</Tag>
							</li>
						{/each}
						{#if editing && editing.length > 0}
							{#each editing as editing}
								<li>
									<SourceLink id={editing.id} name={editing.title} />
									<Tag>Editor</Tag>
								</li>
							{/each}
						{/if}
					</ul>
				{:else}
					<Feedback>No volunteer commitments.</Feedback>
				{/if}
			{:else}
				<Feedback>Unable to load volunteer commitments.</Feedback>
			{/if}
		</Card>

		<Card icon={tokens ?? 0} header="tokens" description="spendable on peer review and gifts">
			<p>
				{#if editable}You have{:else}This scholar has{/if}
				{#if tokens !== null}<Tokens amount={tokens}></Tokens>{:else}an unknown number of{/if} tokens.
			</p>

			<p>
				See <Link to="/scholar/{scholar.getID()}/transactions"
					>{#if transactions === null}your transactions{:else}your {transactions} transactions{/if}</Link
				>.
			</p>
			{#if tokens !== null}
				<Gift
					max={tokens}
					purpose="Gift to peer"
					success="This venue's tokens were successfully gifted."
					transfer={(giftRecipient: string, giftAmount: number, purpose: string) =>
						scholar
							? db.transferTokens(
									scholar.getID(),
									scholar.getID(),
									'scholarid',
									giftRecipient,
									'emailorcid',
									giftAmount,
									purpose
								)
							: undefined}
				/>
			{/if}
		</Card>
		{#if editable}
			<Card icon="⛭" header="settings" description="name, availability, status, email, etc.">
				<EditableText
					text={scholar.getName() ?? ''}
					placeholder="name"
					label="name"
					edit={(text) => db.updateScholarName(scholar.getID(), text)}
				/>
				<EditableText
					text={scholar.getEmail() ?? ''}
					label="email"
					placeholder="email"
					note="Your email will be public and only used to send notifications."
					valid={(text) => /.+@.+\..+/.test(text)}
					edit={(text) => db.updateScholarEmail(scholar.getID(), text)}
				/>

				<p>
					Update your <Link to="https://orcid.org/{scholar.getORCID()}">ORCID Profile</Link> offsite.
				</p>
			</Card>
		{/if}
	</Cards>
</Page>
