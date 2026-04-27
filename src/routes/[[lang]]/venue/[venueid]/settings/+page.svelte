<script lang="ts">
	import Card from '$lib/components/Card.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { ErrorLabel, ScholarLabel, SettingsLabel, VenueLabel } from '$lib/components/Labels.js';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import { getDB } from '$lib/data/CRUD.js';
	import Text from '$lib/locales/Text.svelte';
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
			<Paragraph
				text={(l) => l.page.settings.paragraph.setupSteps}
				inputs={{ venueid: venue.id }}
			/>
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
			<EditableText
				text={venue.inactive ?? ''}
				strings={(l) => l.page.settings.field.inactiveMessage}
				valid={(text) =>
					text.length > 0 ? undefined : (l) => l.page.settings.field.inactiveMessage.invalid ?? ''}
				edit={(text) => db().editVenueInactive(venue.id, text)}
			/>
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
			label={(l) =>
				venue.anonymous_assignments
					? l.page.settings.checkbox.anonymousAssignments.on
					: l.page.settings.checkbox.anonymousAssignments.off}
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
