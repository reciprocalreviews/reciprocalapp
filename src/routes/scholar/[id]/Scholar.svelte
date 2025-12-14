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
	import Tokens from '$lib/components/Tokens.svelte';
	import Gift from '$lib/components/Gift.svelte';
	import Page from '$lib/components/Page.svelte';
	import { validEmail } from '$lib/validation';
	import type {
		AssignmentRow,
		CurrencyID,
		CurrencyRow,
		SubmissionRow,
		TokenRow,
		TransactionRow,
		VenueRow
	} from '$data/types';
	import SubmissionLink from '$lib/components/SubmissionLink.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import { TokenLabel } from '$lib/components/Labels';
	import Dashboard from '$lib/components/Dashboard.svelte';
	import Commitments from './Commitments.svelte';
	import Tasks from './Tasks.svelte';

	let {
		scholar,
		commitments,
		editing,
		minting,
		tokens,
		transactions,
		submissions,
		currencies,
		pending,
		venues,
		reviews
	}: {
		scholar: Scholar;
		commitments: { id: string; invited: boolean; name: string; venue: string; venueid: string }[];
		editing: { id: string; title: string }[] | null;
		tokens: TokenRow[] | null;
		transactions: number | null;
		submissions: SubmissionRow[] | null;
		currencies: CurrencyRow[] | null;
		minting: CurrencyRow[] | null;
		pending: TransactionRow[] | null;
		venues: VenueRow[] | null;
		reviews: (AssignmentRow & { submissions: SubmissionRow })[] | null;
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
				update: (text) => db().updateScholarName(scholar.getID(), text)
			}
		: undefined}
>
	{#snippet subtitle()}Scholar{/snippet}
	{#snippet details()}
		<Status good={scholar.isAvailable()}
			>{scholar.isAvailable() ? 'Available' : 'Unavailable'}</Status
		>
		<Link to="mailto:{scholar.getEmail()}">{scholar.getEmail()}</Link>
		{#if scholar.getORCID()}
			ORCID <Link to="https://orcid.org/{scholar.getORCID()}">{scholar.getORCID()}</Link>
		{/if}
	{/snippet}

	{#if editable}
		{@const time = scholar.getStatusTime()}
		<Tip
			>Your status is public. {#if time}You last updated it on {new Date(
					Date.parse(time)
				).toLocaleString()}.{/if}</Tip
		>
		<Checkbox
			on={scholar.isAvailable()}
			change={(on) => db().updateScholarAvailability(scholar.getID(), on)}
			>I am available to review.</Checkbox
		>

		<EditableText
			inline={false}
			text={scholar.getStatus()}
			placeholder="Explain your current reviewing status to others."
			edit={(text) => db().updateScholarStatus(scholar.getID(), text)}
		/>
	{:else}
		<p>{scholar.getStatus()}</p>
	{/if}

	<Dashboard
		stats={[
			{
				number: submissions?.length,
				title: 'submissions',
				link: `#submissions`
			},
			{ number: tokens?.length, title: 'Tokens', link: `#tokens` },
			{
				number: transactions ?? undefined,
				title: 'Transactions',
				link: `/scholar/${scholar.getID()}/transactions`
			}
		]}
	/>

	{#if editable}
		<Tasks scholar={scholar.getID()} {commitments} {minting} {pending} {reviews}></Tasks>

		<Commitments {commitments} {editing} {minting}></Commitments>
	{/if}

	<h2 id="submissions">Submissions</h2>

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

	<h2 id="tokens">Tokens</h2>

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

	{#if editable}
		<Cards>
			{#if tokens !== null && currencies !== null}
				<Card subheader icon={TokenLabel} header="gift tokens" note="to other scholars">
					<Gift
						{tokens}
						purpose="Gift to peer"
						success="This venue's tokens were successfully gifted."
						{currencies}
						venues={venues ?? []}
						transfer={(
							currency: CurrencyID,
							kind: 'venue' | 'scholar',
							giftRecipient: string,
							giftAmount: number,
							purpose: string
						) =>
							scholar
								? db().transferTokens(
										scholar.getID(),
										currency,
										scholar.getID(),
										'scholarid',
										giftRecipient,
										kind === 'venue' ? 'venueid' : 'emailorcid',
										giftAmount,
										purpose,
										undefined
									)
								: undefined}
					/>
				</Card>
			{/if}
		</Cards>
	{/if}

	{#if editable}
		<h2>Settings</h2>
		<EditableText
			text={scholar.getEmail() ?? ''}
			label="email"
			placeholder="email"
			inline={false}
			note="Your email will be public and only used to send notifications."
			valid={(text) => (validEmail(text) ? undefined : 'Must be a valid email')}
			edit={(text) => db().updateScholarEmail(scholar.getID(), text)}
		/>
	{/if}
</Page>
