<script lang="ts">
	import { getDB } from '$lib/data/CRUD';
	import Link from '$lib/components/Link.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import { getAuth } from '$routes/Auth.svelte';
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
		ScholarRow,
		SubmissionRow,
		TokenRow,
		TransactionRow,
		VenueRow
	} from '$data/types';
	import SubmissionLink from '$lib/components/SubmissionLink.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import { ScholarLabel, SettingsLabel, SubmissionLabel, TokenLabel } from '$lib/components/Labels';
	import Dashboard from '$lib/components/Dashboard.svelte';
	import Commitments from './Commitments.svelte';
	import Tasks from './Tasks.svelte';
	import Subheader from '$lib/components/Subheader.svelte';

	let {
		scholar,
		commitments,
		admins,
		minting,
		tokens,
		transactions,
		submissions,
		currencies,
		pending,
		venues,
		reviews,
		approvals
	}: {
		scholar: Scholar;
		commitments: { id: string; invited: boolean; name: string; venue: string; venueid: string }[];
		admins: { id: string; title: string }[] | null;
		tokens: TokenRow[] | null;
		transactions: number | null;
		submissions: SubmissionRow[] | null;
		currencies: CurrencyRow[] | null;
		minting: CurrencyRow[] | null;
		pending: TransactionRow[] | null;
		venues: VenueRow[] | null;
		reviews: (AssignmentRow & { submissions: SubmissionRow })[] | null;
		approvals: (AssignmentRow & { scholars: ScholarRow; submissions: SubmissionRow })[] | null;
	} = $props();

	const db = getDB();
	const auth = getAuth();

	// Editable if the user is the scholar being viewed.
	let editable = $derived(auth.getUserID() === scholar.getID());
</script>

<Page
	icon={ScholarLabel}
	title={(l) => scholar.getName() ?? l.page.scholar.title}
	breadcrumbs={[]}
	edit={editable
		? {
				placeholder: (l) => l.page.scholar.field.name.placeholder,
				valid: (name: string) =>
					name.trim().length === 0 ? (l) => l.page.scholar.field.name.invalid : undefined,
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
			label={(l) => l.page.scholar.checkbox.available}
		/>

		<EditableText
			inline={false}
			text={scholar.getStatus()}
			strings={(l) => l.page.scholar.field.status}
			edit={(text) => db().updateScholarStatus(scholar.getID(), text)}
		/>
	{:else if scholar.getStatus().trim().length === 0}
		<Feedback text={(l) => l.page.scholar.feedback.noStatus}></Feedback>
	{:else}
		<p>{scholar.getStatus()}</p>
	{/if}

	{#if editable}
		<Dashboard
			stats={[
				{
					number: submissions?.length,
					title: 'submissions',
					link: `#submissions`
				},
				{
					number: tokens?.length,
					title: `Tokens in ${currencies?.length} ${currencies?.length === 1 ? 'currency' : 'currencies'}`,
					link: `#tokens`
				},
				{
					number: transactions ?? undefined,
					title: 'Transactions',
					link: `/scholar/${scholar.getID()}/transactions`
				}
			]}
		/>
	{/if}

	{#if editable}
		<Tasks scholar={scholar.getID()} {commitments} {minting} {pending} {reviews} {approvals}
		></Tasks>
	{/if}

	<Commitments {commitments} {admins} {minting} self={editable}></Commitments>

	{#if submissions === null}
		<Feedback text={(l) => l.page.scholar.feedback.submissionsNotLoaded}></Feedback>
	{:else if submissions.length > 0}
		<Subheader
			icon={SubmissionLabel}
			id="submissions"
			text={(l) => l.page.scholar.header.submissions}
		></Subheader>
		<ul>
			{#each submissions as submission}
				<li><SubmissionLink {submission}></SubmissionLink></li>
			{:else}{/each}
		</ul>
	{/if}

	<Subheader icon={TokenLabel} id="tokens" text={(l) => l.page.scholar.header.tokens}></Subheader>

	{#if tokens === null || currencies === null}
		<Feedback text={(l) => l.page.scholar.feedback.tokensNotLoaded}></Feedback>
	{:else}
		<p>
			{#if editable}You have{:else}This scholar has{/if}:
		</p>
		<ul>
			{#each currencies as currency, index}
				<li data-testid={'currency-' + index}>
					<Tokens amount={tokens.filter((t) => t.currency === currency.id).length} {currency}
					></Tokens>
				</li>
			{:else}
				<Tokens amount={0}></Tokens>
			{/each}
		</ul>
	{/if}

	{#if editable}
		<Cards>
			{#if tokens !== null && currencies !== null}
				<Card subheader icon={TokenLabel} strings={(l) => l.page.scholar.card.gift}>
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

		<Subheader icon={SettingsLabel} text={(l) => l.page.scholar.header.settings}></Subheader>
		<EditableText
			text={scholar.getEmail() ?? ''}
			strings={(l) => l.page.scholar.field.email}
			inline={false}
			valid={(text) =>
				validEmail(text) ? undefined : (l) => l.page.scholar.field.email.invalid ?? ''}
			edit={(text) => db().updateScholarEmail(scholar.getID(), text)}
		/>
	{/if}
</Page>
