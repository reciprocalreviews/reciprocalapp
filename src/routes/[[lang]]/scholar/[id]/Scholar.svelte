<script lang="ts">
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
	import Card from '$lib/components/Card.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import Dashboard from '$lib/components/Dashboard.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Gift from '$lib/components/Gift.svelte';
	import { ScholarLabel, SettingsLabel, SubmissionLabel, TokenLabel } from '$lib/components/Labels';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Status from '$lib/components/Status.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import SubmissionLink from '$lib/components/SubmissionLink.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import { getDB } from '$lib/data/CRUD';
	import type Scholar from '$lib/data/Scholar.svelte';
	import Text from '$lib/locales/Text.svelte';
	import { validEmail } from '$lib/validation';
	import { getAuth } from '$routes/Auth.svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import Commitments from './Commitments.svelte';
	import Tasks from './Tasks.svelte';

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
		outgoingPending,
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
		outgoingPending: TransactionRow[] | null;
		venues: VenueRow[] | null;
		reviews: (AssignmentRow & { submissions: SubmissionRow })[] | null;
		approvals: (AssignmentRow & { scholars: ScholarRow; submissions: SubmissionRow })[] | null;
	} = $props();

	const db = getDB();
	const auth = getAuth();
	const locale = getLocaleContext();

	// Editable if the user is the scholar being viewed.
	let editable = $derived(auth().getUserID() === scholar.getID());
	let anonymous = $derived(editable && scholar.getName() === null);
</script>

<Page
	icon={ScholarLabel}
	title={(l) => scholar.getName() ?? l.page.scholar.title}
	breadcrumbs={[]}
	wobble={anonymous}
	edit={editable
		? {
				placeholder: (l) => l.page.scholar.field.name.placeholder,
				valid: (name: string) =>
					name.trim().length === 0 ? (l) => l.page.scholar.field.name.invalid : undefined,
				update: (text) => db().updateScholarName(scholar.getID(), text)
			}
		: undefined}
>
	{#snippet subtitle()}<Text path={(l) => l.page.scholar.subtitle} />{/snippet}
	{#if anonymous}
		<Feedback inline={false} text={(l) => l.page.scholar.feedback.noName} />
	{/if}
	{#snippet details()}
		<Status
			good={scholar.isAvailable()}
			label={(l) =>
				scholar.isAvailable() ? l.page.scholar.status.available : l.page.scholar.status.unavailable}
		/>
		<Link to="mailto:{scholar.getEmail()}">{scholar.getEmail()}</Link>
		{#if scholar.getORCID()}
			ORCID <Link to="https://orcid.org/{scholar.getORCID()}">{scholar.getORCID()}</Link>
		{/if}
	{/snippet}

	{#if editable}
		{@const time = scholar.getStatusTime()}
		<Tip
			>{locale().page.scholar.tip.status}
			{#if time}{new Date(Date.parse(time)).toLocaleString()}{/if}</Tip
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
		<Paragraph text={() => scholar.getStatus()} />
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
		<Tasks scholar={scholar.getID()} {commitments} {minting} {pending} {outgoingPending} {reviews} {approvals}
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
		<Paragraph
			text={(l) =>
				editable ? l.page.scholar.paragraph.youHave : l.page.scholar.paragraph.thisScholarHas}
		/>
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
						purpose={locale().page.scholar.card.gift.purpose}
						success={locale().page.scholar.card.gift.success}
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
