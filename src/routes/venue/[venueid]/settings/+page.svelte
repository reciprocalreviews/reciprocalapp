<script lang="ts">
	import Card from '$lib/components/Card.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { ErrorLabel, ScholarLabel, SettingsLabel, VenueLabel } from '$lib/components/Labels.js';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
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
	<h1>Oops.</h1>
	<Feedback error>Unknown venue.</Feedback>
{:else if !scholar}
	<h1>Oops.</h1>
	<Feedback error><Link to="/login">Log in</Link> to view this page.</Feedback>
{:else if !venue.admins.includes(scholar.id)}
	<h1>Oops.</h1>
	<Page
		icon={ErrorLabel}
		title={venue.title}
		breadcrumbs={[
			['/venues', 'Venues'],
			[`/venue/${venue.id}`, venue.title]
		]}
	>
		{#snippet subtitle()}Settings{/snippet}
		<Feedback error>Only admins of this venue can view this page.</Feedback>
	</Page>
{:else}
	<Page
		icon={VenueLabel}
		title={venue.title}
		breadcrumbs={[
			['/venues', 'Venues'],
			[`/venue/${venue.id}`, venue.title]
		]}
	>
		{#snippet subtitle()}Settings{/snippet}
		<p>Welcome venue admin! You can manage this venue's settings here.</p>

		<Card
			subheader
			header="Setup"
			icon={SettingsLabel}
			note="Steps to get your venue ready for volunteers and submissions"
			expand={venue.inactive !== null}
		>
			<p>
				Hello venue admin! Are you ready to integrate into your reviewing system? There are a few
				steps:
			</p>
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

		<Subheader icon={SettingsLabel}>Status</Subheader>

		<Checkbox
			on={venue.inactive !== null}
			change={(on) => db().editVenueInactive(venue.id, on ? 'This venue is not active.' : null)}
		>
			<strong>Inactive venue</strong>: Scholars cannot volunteer, submit, or otherwise interact with
			this venue.
		</Checkbox>

		{#if venue.inactive !== null}
			<div style="margin-left: var(--spacing)">
				<EditableText
					text={venue.inactive ?? ''}
					label="Inactive message"
					placeholder="e.g., We're currently configuring the venue."
					valid={(text) => (text.length > 0 ? undefined : 'You must include a message')}
					edit={(text) => db().editVenueInactive(venue.id, text)}
				/>
			</div>
		{/if}

		<Subheader icon={SettingsLabel}>Compensation</Subheader>

		<EditableText
			text={venue.welcome_amount.toString()}
			label="Welcome tokens (received when first volunteering)"
			placeholder="e.g., 40"
			valid={(text) => (validInteger(text) ? undefined : 'Must be a whole number')}
			edit={(text) => db().editVenueWelcomeAmount(venue.id, parseInt(text))}
		/>

		<EditableText
			text={venue.submission_cost.toString()}
			label="Submission cost (price to submit a manuscript to the venue)"
			placeholder="e.g., 40"
			valid={(text) => (validInteger(text) ? undefined : 'Must be a whole number')}
			edit={(text) => db().editVenueSubmissionCost(venue.id, parseInt(text))}
		/>

		<Subheader id="roles" icon={ScholarLabel}>Roles</Subheader>

		<Tip>
			Configure your venue's volunteer roles below, create roles such as <em>reviewer</em>,
			<em>program commitee</em>, <em>associate editor</em> to represent the different kinds of contributions
			volunteers can make to this venue.
		</Tip>

		<Checkbox
			on={venue.anonymous_assignments}
			change={(on) => db().editVenueAnonymousAssignments(venue.id, on)}
		>
			{#if venue.anonymous_assignments}
				<strong>Anonymous assignments</strong>: Authors and conflicted scholars cannot see who is
				assigned to review their submissions.
			{:else}
				<strong>Visible assignments</strong>: Authors and conflicted scholars can see who is
				assigned to review their submissions. This is open reviewing.
			{/if}
		</Checkbox>

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
