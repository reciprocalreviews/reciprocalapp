<script lang="ts">
	import Card from '$lib/components/Card.svelte';
	import Text from '$lib/locales/Text.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { ErrorLabel, ScholarLabel, SettingsLabel, VenueLabel } from '$lib/components/Labels.js';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import { getDB } from '$lib/data/CRUD.js';
	import { validInteger } from '$lib/validation.js';
	import Roles from '../Roles.svelte';

	let { data } = $props();
	let { venue, scholar, roles, volunteers, currency, minters, types, compensation } =
		$derived(data);

	const db = getDB();
</script>

{#if venue === null || currency === null}
	<Page icon={ErrorLabel} title={(l) => l.page.error.title} breadcrumbs={[]}>
		<Feedback error text={(l) => l.page.settings.feedback.unknownVenue} />
	</Page>
{:else if !scholar}
	<Page icon={ErrorLabel} title={(l) => l.page.error.title} breadcrumbs={[]}>
		<Feedback error text={(l) => l.page.settings.feedback.logIn} />
	</Page>
{:else if !venue.admins.includes(scholar.id)}
	<Page icon={ErrorLabel} title={venue.title} breadcrumbs={[[`/venue/${venue.id}`, venue.title]]}>
		{#snippet subtitle()}<Text path={(l) => l.page.settings.subtitle} />{/snippet}
		<Feedback error text={(l) => l.page.settings.feedback.adminsOnly} />
	</Page>
{:else}
	<Page
		icon={VenueLabel}
		title={venue.title}
		breadcrumbs={[[`/venue/${venue.id}`, venue.title]]}
		edit={{
			placeholder: (l) => l.page.venue.field.name.placeholder,
			valid: (text) => (text.length > 0 ? undefined : (l) => l.page.venue.field.name.invalid),
			update: (text) => db().editVenueTitle(venue.id, text)
		}}
	>
		{#snippet subtitle()}<Text path={(l) => l.page.settings.subtitle} />{/snippet}
		<Paragraph text={(l) => l.page.settings.paragraph.welcome} />

		<Card
			subheader
			strings={(l) => l.page.venue.card.setup}
			icon={SettingsLabel}
			expand={venue.inactive !== null}
			testid="setup-card"
		>
			<Paragraph text={(l) => l.page.settings.paragraph.setupIntro} />
			<ol>
				<li>
					Update the inactive message in the settings below, so your community know you're busy
					configuring things.
				</li>
				<li>Run a community process to decide on all settings below.</li>
				<li>
					Include this venue's <Link to={`/venue/${venue.id}/submissions/new`}>payment link</Link> in
					author instructions and submission confirmations, prompting authors to pay after submission.
					If you want the manuscript ID to be populated automatically and your reviewing platform supports
					it, you can use the URL
					<code>https://reciprocal.reviews/venue/{venue.id}/submission/new?id=[ID]</code>, but
					replace
					<code>[ID]</code> with the variable your system uses for manuscript ID.
				</li>
				<li>
					Update your reviewing platform's <strong>review submission</strong> notification email to
					prompt the scholar receiving it with a link to the submission:
					<code>https://reciprocal.reviews/venue/{venue.id}/submission/[id]</code>, but replace
					<code>[id]</code> with the variable your system uses for manuscript ID. In the email,
					prompt them to add the reviewer to the submission (if they haven't already), evaluate the
					review, and if it meets your venue's review quality requirements, press the
					<strong>Complete</strong> button to pay for their work.
				</li>
				<li>
					When you're ready to launch, remove the <strong>inactive message</strong> in the settings below,
					and the venue will be open for volunteering.
				</li>
			</ol>
		</Card>

		<Subheader icon={SettingsLabel} text={(l) => l.page.settings.header.status} />

		<Tip><Text path={(l) => l.page.settings.tip.inactive} /></Tip>

		<Checkbox
			testid="inactive-checkbox"
			on={venue.inactive !== null}
			change={(on) => db().editVenueInactive(venue.id, on ? 'This venue is not active.' : null)}
			label={(l) => l.page.settings.checkbox.inactive}
		/>

		{#if venue.inactive !== null}
			<div style="margin-left: var(--spacing)">
				<EditableText
					text={venue.inactive ?? ''}
					strings={(l) => l.page.settings.field.inactiveMessage}
					valid={(text) =>
						text.length > 0
							? undefined
							: (l) => l.page.settings.field.inactiveMessage.invalid ?? ''}
					edit={(text) => db().editVenueInactive(venue.id, text)}
				/>
			</div>
		{/if}

		<Subheader icon={SettingsLabel} text={(l) => l.page.settings.header.compensation} />

		<Tip><Text path={(l) => l.page.settings.tip.compensation} /></Tip>

		<EditableText
			text={venue.welcome_amount.toString()}
			strings={(l) => l.page.settings.field.welcomeTokens}
			valid={(text) =>
				validInteger(text) ? undefined : (l) => l.page.settings.field.welcomeTokens.invalid ?? ''}
			edit={(text) => db().editVenueWelcomeAmount(venue.id, parseInt(text))}
		/>

		<EditableText
			text={venue.submission_cost.toString()}
			strings={(l) => l.page.settings.field.submissionCost}
			valid={(text) =>
				validInteger(text) ? undefined : (l) => l.page.settings.field.submissionCost.invalid ?? ''}
			edit={(text) => db().editVenueSubmissionCost(venue.id, parseInt(text))}
		/>

		<Subheader id="roles" icon={ScholarLabel} text={(l) => l.page.settings.header.roles} />

		<Tip><Text markdown path={(l) => l.page.settings.tip.roles} /></Tip>

		<Checkbox
			on={venue.anonymous_assignments}
			change={(on) => db().editVenueAnonymousAssignments(venue.id, on)}
			label={(l) => venue.anonymous_assignments ? l.page.settings.checkbox.anonymousAssignments.on : l.page.settings.checkbox.anonymousAssignments.off}
		/>

		<Roles
			{venue}
			scholar={scholar?.id}
			{roles}
			{volunteers}
			isAdmin={true}
			{currency}
			{minters}
			{types}
			{compensation}
		/>
	</Page>
{/if}
