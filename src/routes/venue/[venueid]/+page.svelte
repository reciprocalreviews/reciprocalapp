<script lang="ts">
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Link from '$lib/components/Link.svelte';
	import { getDB } from '$lib/data/CRUD';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Page from '$lib/components/Page.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Card from '$lib/components/Card.svelte';
	import { DeleteLabel, SettingsLabel, TokenLabel } from '$lib/components/Labels';
	import { validInteger, validURLError } from '$lib/validation';
	import { handle } from '../../feedback.svelte';
	import Roles from './Roles.svelte';
	import type { PageData } from './$types';
	import Gift from '$lib/components/Gift.svelte';
	import { type CurrencyID } from '$data/types';
	import Dashboard from '$lib/components/Dashboard.svelte';
	import CurrencyLink from '$lib/components/CurrencyLink.svelte';
	import Tip from '$lib/components/Tip.svelte';

	let { data }: { data: PageData } = $props();
	const { venue, currency, minters, scholar, roles, volunteers, tokens, submissionCount, venues } =
		$derived(data);

	const db = getDB();
	let editor = $derived(scholar && venue && venue.editors.includes(scholar.id));
</script>

{#if venue === null}
	<Page title="Unknown venue" breadcrumbs={[]}>
		<p>Unable to find this venue.</p>
	</Page>
{:else}
	<Page
		title={venue.title}
		breadcrumbs={[[`/venues`, 'Venues']]}
		edit={editor
			? {
					placeholder: 'Title',
					valid: (text) => (text.length > 0 ? undefined : 'Must include a title'),
					update: (text) => db().editVenueTitle(venue.id, text)
				}
			: undefined}
	>
		{#snippet subtitle()}Venue{/snippet}
		{#snippet details()}<Link to={venue.url}>{venue.url}</Link>{/snippet}

		<!-- Show the description -->
		{#if editor}
			<EditableText
				text={venue.description}
				placeholder="Venue description."
				inline={false}
				edit={(text) => db().editVenueDescription(venue.id, text)}
			/>
		{:else}
			<p>
				{#if venue.description.length === 0}<em>No description.</em>{:else}{venue.description}{/if}
			</p>
		{/if}

		<ul>
			<li>
				This venue is edited by
				{#each venue.editors as editorID, index}
					<ScholarLink id={editorID} />{#if editor && venue.editors.length > 1}
						&nbsp;<Button
							tip="Remove editor"
							active={venue.editors.length > 1}
							warn="Are you sure you want to remove this editor?"
							action={() =>
								handle(
									db().editVenueEditors(
										venue.id,
										venue.editors.filter((ed) => ed !== editorID)
									)
								)}>{DeleteLabel}</Button
						>{/if}{#if index < venue.editors.length - 1},{/if}.
				{/each}
			</li>
			<!-- Prompt to pay -->
			<li>
				Submitted a manuscript? <Link to={`${venue.id}/submissions/new`}>Pay</Link> to start peer review.
			</li>
			<!-- Prompt to volunteer -->
			<li>
				Need tokens to pay? <Link to="#roles">Volunteer to review</Link>.
			</li>
			<!-- Key details about costs. -->
			<li>
				This venue uses {#if currency}the <CurrencyLink {currency}>
						{TokenLabel} {currency.name}</CurrencyLink
					>{:else}an unknown{/if}
				currency.
			</li>
		</ul>

		<Dashboard
			stats={[
				{
					number: venue.welcome_amount ?? undefined,
					icon: TokenLabel,
					title: 'tokens for new volunteers'
				},
				{
					number: venue.submission_cost ?? undefined,
					icon: TokenLabel,
					title: 'tokens for new submissions'
				},
				{
					number: volunteers?.length ?? undefined,
					title: 'volunteers',
					link: `/venue/${venue.id}/volunteers`
				},
				{
					number: submissionCount ?? undefined,
					title: 'submissions visible to you',
					link: `/venue/${venue.id}/submissions`
				},
				{ number: tokens?.length, title: 'tokens', link: `/venue/${venue.id}/transactions` }
			]}
		></Dashboard>

		{#if editor}
			<Tip border>
				<p>
					Hello editor. Are you ready to integrate into your reviewing system? There are a few
					steps:
				</p>
				<ol>
					<li>
						Run a community process to decide the <Link to="#roles">roles</Link> and <Link
							to="settings">settings</Link
						> below about compensation and bidding. Once decided, set them up below.
					</li>
					<li>
						Include this venue's <Link to={`${venue.id}/submissions/new`}>payment link</Link> in author
						instructions and submission confirmations, prompting authors to pay after submission. If you
						want the manuscript ID to be populated automatically and your reviewing platform supports
						it, you can use the URL
						<code>https://reciprocal.reviews/venue/{venue.id}/submission/new?id=[ID]</code>, but
						replace
						<code>[ID]</code> with the variable your system uses for manuscript ID.
					</li>
					<li>
						Update your reviewing platform's <strong>review submission</strong> notification email
						to prompt the scholar receiving it with a link to the submission:
						<code>https://reciprocal.reviews/venue/{venue.id}/submission/[id]</code>, but replace
						<code>[id]</code> with the variable your system uses for manuscript ID. In the email,
						prompt them to add the reviewer to the submission (if they haven't already), evaluate
						the review, and if it meets your venue's review quality requirements, press the
						<strong>Complete</strong> button to pay for their work.
					</li>
				</ol>
			</Tip>
		{/if}

		<h2 id="roles">Roles</h2>

		{#if roles && currency}
			<Roles
				{venue}
				scholar={scholar?.id}
				{roles}
				{volunteers}
				editor={editor === true}
				{currency}
				{minters}
			/>
		{:else}
			<Feedback error>Couldn't load venue's roles.</Feedback>
		{/if}

		{#if editor}
			<h2 id="settings">Settings</h2>

			<Cards>
				<Card group="editors" icon="🎁" header="gift" note="Send tokens to a scholar" full>
					{#if scholar && currency !== null}
						<Gift
							{tokens}
							purpose="Venue gift"
							success="Your tokens were successfully gifted."
							currencies={[currency]}
							venues={venues ?? []}
							transfer={(
								currency: CurrencyID,
								kind: 'venue' | 'scholar',
								giftRecipient: string,
								giftAmount: number,
								purpose: string
							) =>
								currency !== null
									? db().transferTokens(
											scholar.id,
											currency,
											venue.id,
											'venueid',
											giftRecipient,
											kind === 'venue' ? 'venueid' : 'emailorcid',
											giftAmount,
											purpose,
											undefined
										)
									: undefined}
						/>
					{/if}
				</Card>
				<Card
					group="editors"
					icon={SettingsLabel}
					header="settings"
					note="Update title, url, costs, etc."
					expand
					full
				>
					<EditableText
						text={venue.url}
						label="URL"
						placeholder="https://..."
						valid={validURLError}
						edit={(text) => db().editVenueURL(venue.id, text)}
					/>
					<EditableText
						text={venue.welcome_amount.toString()}
						label="Welcome tokens"
						placeholder="e.g., 40"
						valid={(text) => (validInteger(text) ? undefined : 'Must be a whole number')}
						edit={(text) => db().editVenueWelcomeAmount(venue.id, parseInt(text))}
					/>
					<EditableText
						text={venue.submission_cost.toString()}
						label="Submission cost"
						placeholder="e.g., 40"
						valid={(text) => (validInteger(text) ? undefined : 'Must be a whole number')}
						edit={(text) => db().editVenueSubmissionCost(venue.id, parseInt(text))}
					/>
				</Card>
			</Cards>
		{/if}
	</Page>
{/if}
