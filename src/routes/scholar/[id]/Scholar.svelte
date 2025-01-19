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
	import Page from '$lib/components/Page.svelte';
	import Row from '$lib/components/Row.svelte';
	import { validEmail } from '$lib/validation';

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

<Page title={scholar.getName() ?? 'anonymous'} breadcrumbs={[]}>
	{#snippet subtitle()}Scholar{/snippet}
	{#snippet details()}
		<Link to="mailto:{scholar.getEmail()}">{scholar.getEmail()}</Link>
		{#if scholar.getORCID()}
			<Link to="https://orcid.org/{scholar.getORCID()}">{scholar.getORCID()}</Link>
		{/if}
	{/snippet}

	{#if editable}
		<EditableText
			inline={false}
			text={scholar.getStatus()}
			placeholder="Explain your current reviewing status to others."
			edit={(text) => db.updateScholarStatus(scholar.getID(), text)}
			note="Your status is public and will be shown here."
		/>
	{:else}
		<p>{scholar.getStatus()}</p>
	{/if}

	<Row>
		{#if editable}
			<Checkbox
				on={scholar.isAvailable()}
				change={(on) => db.updateScholarAvailability(scholar.getID(), on)}
				>I am available to review.</Checkbox
			>
		{/if}
		<Status good={scholar.isAvailable()}
			>{scholar.isAvailable() ? 'Available' : 'Unavailable'}</Status
		>
	</Row>

	<Cards>
		<Card
			icon={commitments.length + (editing?.length ?? 0)}
			header="commitments"
			note="Venues volunteered for"
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

		<Card icon={tokens ?? 0} header="tokens" note="Spendable on peer review and gifts">
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
			<Card icon="⛭" header="settings" note="Name, availability, status, email, etc.">
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
					inline={false}
					note="Your email will be public and only used to send notifications."
					valid={(text) => (validEmail(text) ? undefined : 'Must be a valid email')}
					edit={(text) => db.updateScholarEmail(scholar.getID(), text)}
				/>
			</Card>
		{/if}
	</Cards>
</Page>
