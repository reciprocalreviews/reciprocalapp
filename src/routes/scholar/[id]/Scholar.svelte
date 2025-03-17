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
	import { validEmail } from '$lib/validation';
	import type { CurrencyID, CurrencyRow, SubmissionRow, TokenRow } from '$data/types';
	import SubmissionLink from '$lib/components/SubmissionLink.svelte';

	let {
		scholar,
		commitments,
		editing,
		tokens,
		transactions,
		submissions,
		currencies
	}: {
		scholar: Scholar;
		commitments: { name: string; venue: string; venueid: string }[];
		editing: { id: string; title: string }[] | null;
		tokens: TokenRow[] | null;
		transactions: number | null;
		submissions: SubmissionRow[] | null;
		currencies: CurrencyRow[] | null;
	} = $props();

	const db = getDB();
	const auth = getAuth();

	// Editable if the user is the scholar being viewed.
	let editable = $derived(auth.getUserID() === scholar.getID());
</script>

<Page
	title={scholar.getName() ?? 'anonymous'}
	breadcrumbs={[]}
	edit={editable
		? {
				placeholder: 'Name',
				valid: (name: string) => (name.trim().length === 0 ? 'Name cannot be empty' : undefined),
				update: (text) => db.updateScholarName(scholar.getID(), text)
			}
		: undefined}
>
	{#snippet subtitle()}Scholar{/snippet}
	{#snippet details()}
		<Link to="mailto:{scholar.getEmail()}">{scholar.getEmail()}</Link>
		<Status good={scholar.isAvailable()}
			>{scholar.isAvailable() ? 'Available' : 'Unavailable'}</Status
		>
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

	{#if editable}
		<Checkbox
			on={scholar.isAvailable()}
			change={(on) => db.updateScholarAvailability(scholar.getID(), on)}
			>I am available to review.</Checkbox
		>
	{/if}

	<Cards>
		<Card
			full
			icon={submissions === null ? '📝' : submissions.length}
			header="submissions"
			note="Submissions in review"
		>
			{#if submissions}
				<ul>
					{#each submissions as submission}
						<li><SubmissionLink {submission}></SubmissionLink></li>
					{:else}
						<Feedback>No submissions.</Feedback>
					{/each}
				</ul>
			{:else}
				<Feedback>Unable to load submissions.</Feedback>
			{/if}
		</Card>

		<Card
			icon={commitments.length + (editing?.length ?? 0)}
			header="commitments"
			note="Venues volunteered for"
		>
			<ul>
				{#if editing}
					{#if editing.length > 0}
						{#each editing as editing}
							<li>
								<SourceLink id={editing.id} name={editing.title} />
								<Tag>Editor</Tag>
							</li>
						{/each}
					{/if}
				{:else}
					<li><Feedback>Unable to load editing commitments.</Feedback></li>
				{/if}
				{#if commitments}
					{#if commitments.length > 0}
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
					{:else if editing?.length === 0}
						<li><Feedback>No volunteer commitments.</Feedback></li>
					{/if}
				{:else}
					<li><Feedback>Unable to load volunteer commitments.</Feedback></li>
				{/if}
			</ul>
		</Card>

		<Card
			icon={tokens === null ? '?' : tokens.length}
			header="tokens"
			note="Spendable on peer review and gifts"
		>
			<p>
				{#if editable}You have{:else}This scholar has the following tokens:{/if}
				{#if tokens === null}
					<Feedback>Unable to load tokens.</Feedback>
				{:else if currencies === null}
					<Feedback>Unable to load currencies.</Feedback>
				{:else}
					{#each currencies as currency}
						<Tokens amount={tokens.filter((t) => t.currency === currency.id).length} {currency}
						></Tokens>
					{:else}
						<Tokens amount={0}></Tokens>
					{/each}
				{/if}
			</p>

			<p>
				See <Link to="/scholar/{scholar.getID()}/transactions"
					>{#if transactions === null}your transactions{:else}your {transactions} transactions{/if}</Link
				>.
			</p>
			{#if tokens !== null && currencies !== null}
				<Gift
					{tokens}
					purpose="Gift to peer"
					success="This venue's tokens were successfully gifted."
					{currencies}
					transfer={(
						currency: CurrencyID,
						giftRecipient: string,
						giftAmount: number,
						purpose: string
					) =>
						scholar
							? db.transferTokens(
									scholar.getID(),
									currency,
									scholar.getID(),
									'scholarid',
									giftRecipient,
									'emailorcid',
									giftAmount,
									purpose,
									undefined
								)
							: undefined}
				/>
			{/if}
		</Card>
		{#if editable}
			<Card icon="⚙️" header="settings" note="Email, etc.">
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
