<script lang="ts">
	import Card from '$lib/components/Card.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import CopyButton from '$lib/components/CopyButton.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { ErrorLabel, ScholarLabel, SettingsLabel, VenueLabel } from '$lib/components/Labels.js';
	import Options from '$lib/components/Options.svelte';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Slider from '$lib/components/Slider.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import { getDB } from '$lib/data/CRUD.js';
	import { PLATFORMS } from '$lib/data/reviewingPlatforms';
	import Text from '$lib/locales/Text.svelte';
	import { validInteger } from '$lib/validation.js';
	import { getLocaleContext } from '$routes/Contexts';
	import { handle } from '$routes/feedback.svelte';
	import PreferenceLevels from '../PreferenceLevels.svelte';
	import Roles from '../Roles.svelte';

	let { data } = $props();
	let {
		venue,
		scholar,
		roles,
		volunteers,
		currency,
		minters,
		types,
		compensation,
		preferenceLevels
	} = $derived(data);

	const db = getDB();
	const locale = getLocaleContext();

	/** Selected reviewing-platform id for the email-templates section (#113).
	 * Local state only — not persisted to the venue yet. */
	let platformId = $state<string | undefined>('hotcrp');
	const selectedPlatform = $derived(
		PLATFORMS.find((p) => p.id === platformId) ?? PLATFORMS[0]
	);

	/** Substitute the template body's placeholders. */
	function renderTemplate(body: string, venueTitle: string, venueId: string): string {
		return body
			.replaceAll('{venue}', venueTitle)
			.replaceAll('{venueid}', venueId)
			.replaceAll('{manuscriptVar}', selectedPlatform.submissionVar);
	}

	/** Section ids declared once; reused throughout so typos at use sites are
	 * caught at compile time. */
	const POLICIES = 'policies';
	const COMPENSATION = 'compensation';
	const ROLES = 'roles';
	const VISIBILITY = 'visibility';
	const PREFERENCE_LEVELS = 'preferenceLevels';
	const TEMPLATES = 'templates';
	const BULK_IMPORT = 'bulkImport';
	const STATUS = 'status';
	/** Display order. Numbering is derived from this list filtered by
	 * `visibleSteps` so hiding a section (e.g. preference levels when nothing
	 * is biddable) renumbers the rest. */
	const STEPS_IN_ORDER = [
		POLICIES,
		COMPENSATION,
		ROLES,
		VISIBILITY,
		PREFERENCE_LEVELS,
		TEMPLATES,
		BULK_IMPORT,
		STATUS
	] as const;
	type StepId = (typeof STEPS_IN_ORDER)[number];

	const hasBiddableRole = $derived((roles ?? []).some((r) => r.biddable));
	const visibleSteps = $derived(
		STEPS_IN_ORDER.filter((s) => s !== PREFERENCE_LEVELS || hasBiddableRole)
	);
	function stepNumber(id: StepId): number {
		return visibleSteps.indexOf(id) + 1;
	}
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

		<!-- Step 1: Decide policies -->
		<Subheader
			id="policies"
			icon={SettingsLabel}
			number={stepNumber(POLICIES)}
			text={(l) => l.page.settings.header.policies}
		/>

		<Tip><Text path={(l) => l.page.settings.tip.policies} /></Tip>

		<Paragraph text={(l) => l.page.settings.paragraph.policies} />

		<!-- Step 2: Compensation -->
		<Subheader
			id="compensation"
			icon={SettingsLabel}
			number={stepNumber(COMPENSATION)}
			text={(l) => l.page.settings.header.compensation}
		/>

		<Tip><Text path={(l) => l.page.settings.tip.compensation} /></Tip>

		<EditableText
			text={venue.welcome_amount.toString()}
			strings={(l) => l.page.settings.field.welcomeTokens}
			valid={(text) =>
				validInteger(text) ? undefined : (l) => l.page.settings.field.welcomeTokens.invalid ?? ''}
			edit={(text) => db().editVenueWelcomeAmount(venue.id, parseInt(text))}
			testid="venue-welcome-amount"
		/>

		<!-- Step 3: Roles -->
		<Subheader
			id="roles"
			icon={ScholarLabel}
			number={stepNumber(ROLES)}
			text={(l) => l.page.settings.header.roles}
		/>

		<Tip><Text markdown path={(l) => l.page.settings.tip.roles} /></Tip>

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
			startCollapsed
		/>

		<!-- Step 4: Visibility -->
		<Subheader
			id="visibility"
			icon={SettingsLabel}
			number={stepNumber(VISIBILITY)}
			text={(l) => l.page.settings.header.visibility}
		/>

		<Tip><Text path={(l) => l.page.settings.tip.doneVisibility} /></Tip>

		<Checkbox
			on={venue.anonymous_assignments}
			change={(on) => db().editVenueAnonymousAssignments(venue.id, on)}
			label={(l) =>
				venue.anonymous_assignments
					? l.page.settings.checkbox.anonymousAssignments.on
					: l.page.settings.checkbox.anonymousAssignments.off}
		/>

		<Slider
			min={0}
			max={365}
			step={7}
			value={venue.done_visibility_days}
			strings={(l) => l.page.settings.slider.doneVisibility}
			change={(days) => handle(db().editVenueDoneVisibilityDays(venue.id, days))}
			immediately={false}
			testid="done-visibility-days"
		/>

		<!-- Step 5: Bid preference levels (only when at least one role is biddable) -->
		{#if hasBiddableRole}
			<Subheader
				id="preference-levels"
				icon={SettingsLabel}
				number={stepNumber(PREFERENCE_LEVELS)}
				text={(l) => l.page.settings.header.preferenceLevels}
			/>

			<Tip><Text path={(l) => l.page.settings.tip.preferenceLevels} /></Tip>

			<PreferenceLevels {venue} levels={preferenceLevels ?? []} />
		{/if}

		<!-- Step 6: Email templates -->
		<Subheader
			id="templates"
			icon={SettingsLabel}
			number={stepNumber(TEMPLATES)}
			text={(l) => l.page.settings.header.templates}
		/>

		<Tip><Text markdown path={(l) => l.page.settings.tip.templates} /></Tip>

		<Options
			strings={(l) => l.page.settings.options.platform}
			value={platformId}
			options={PLATFORMS.map((p) => ({ label: p.name, value: p.id }))}
			onChange={(value) => (platformId = value)}
		/>

		{#each ['payment', 'acknowledgement', 'compensation'] as kind (kind)}
			{@const tpl =
				kind === 'payment'
					? locale().page.settings.template.payment
					: kind === 'acknowledgement'
						? locale().page.settings.template.acknowledgement
						: locale().page.settings.template.compensation}
			{@const rendered = renderTemplate(tpl.body, venue.title, venue.id)}
			<Card
				icon={SettingsLabel}
				subheader
				expand
				strings={(_l) => ({ header: tpl.title, note: '' })}
			>
				<pre data-testid="template-{kind}">{rendered}</pre>
				<CopyButton text={rendered} testid="template-{kind}-copy" />
			</Card>
		{/each}

		<!-- Step 7: Bulk import -->
		<Subheader
			id="bulk-import"
			icon={SettingsLabel}
			number={stepNumber(BULK_IMPORT)}
			text={(l) => l.page.settings.header.bulkImport}
		/>

		<Tip>
			<Text
				markdown
				path={(l) => l.page.settings.tip.bulkImport}
				inputs={{ venueid: venue.id }}
			/>
		</Tip>

		<!-- Step 8: Activate (the last thing you do) -->
		<Subheader
			id="status"
			icon={SettingsLabel}
			number={stepNumber(STATUS)}
			text={(l) => l.page.settings.header.status}
		/>

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
				testid="venue-inactive-message"
			/>
		{/if}
	</Page>
{/if}

<style>
	pre {
		white-space: pre-wrap;
		word-break: break-word;
		background: var(--alternating-color);
		padding: var(--spacing);
		border-radius: var(--roundedness);
		font-family: inherit;
		font-size: var(--small-font-size);
		margin: 0;
	}
</style>
