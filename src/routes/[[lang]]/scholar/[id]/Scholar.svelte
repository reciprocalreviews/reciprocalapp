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
	import Button from '$lib/components/Button.svelte';
	import Card from '$lib/components/Card.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import Dashboard from '$lib/components/Dashboard.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Gift from '$lib/components/Gift.svelte';
	import { ScholarLabel, SettingsLabel, SubmissionLabel, TokenLabel } from '$lib/components/Labels';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Status from '$lib/components/Status.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import SubmissionLink from '$lib/components/SubmissionLink.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import VerifyEmail from '$lib/components/VerifyEmail.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { handle } from '$routes/feedback.svelte';
	import type Scholar from '$lib/data/Scholar.svelte';
	import Text from '$lib/locales/Text.svelte';
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
			testid="available-checkbox"
		/>

		<EditableText
			inline={false}
			text={scholar.getStatus()}
			strings={(l) => l.page.scholar.field.status}
			edit={(text) => db().updateScholarStatus(scholar.getID(), text)}
			testid="status"
		/>
	{:else if scholar.getStatus().trim().length === 0}
		<Feedback text={(l) => l.page.scholar.feedback.noStatus}></Feedback>
	{:else}
		<Paragraph text={() => scholar.getStatus()} />
	{/if}

	{#if editable && scholar.getEmail() === null}
		<Feedback
			inline={false}
			testid="email-onboarding"
			text={(l) => l.page.scholar.feedback.addEmail}
		/>
		<VerifyEmail />
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
		<Tasks
			scholar={scholar.getID()}
			{commitments}
			{minting}
			{pending}
			{outgoingPending}
			{reviews}
			{approvals}
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
				<Card
					subheader
					icon={TokenLabel}
					strings={(l) => l.page.scholar.card.gift}
					testid="scholar-gift-card"
				>
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

		{#if scholar.getEmail() !== null}
			<Subheader icon={SettingsLabel} text={(l) => l.page.scholar.header.settings}></Subheader>
			<VerifyEmail current={scholar.getEmail()} />
		{/if}

		{#if editable}
			<!-- The data rights the terms page promises (page.terms.paragraph.rights),
			     shown only to the scholar themselves. Erasure is deliberately placed
			     below everything else and behind the Button's confirm step: it cannot
			     be undone, and the ORCID identity behind the account goes with it. -->
			<Subheader icon={SettingsLabel} text={(l) => l.page.scholar.privacy.header}></Subheader>
			<Paragraph text={(l) => l.page.scholar.privacy.about}></Paragraph>
			<div class="privacy">
				<Button
					strings={(l) => l.page.scholar.privacy.export}
					action={() => {
						// A plain navigation rather than a fetch: the endpoint answers with
						// Content-Disposition: attachment, so the browser saves the file
						// without this page having to hold a copy of it in memory.
						window.location.href = `/scholar/${scholar.getID()}/export`;
					}}
				/>
				<Button
					strings={(l) => l.page.scholar.privacy.erase}
					action={async () => {
						// handle() returns false when the action failed, having already
						// posted the error to the feedback bus.
						const erased = await handle(db().eraseScholar(scholar.getID()));
						// The session outlives the identity behind it, so sign out rather
						// than leaving them on a page for an account that no longer exists.
						if (erased !== false) await auth().signOut();
					}}
				/>
			</div>
		{/if}
	{/if}
</Page>

<style>
	.privacy {
		display: flex;
		flex-wrap: wrap;
		gap: var(--spacing);
		align-items: center;
	}
</style>
