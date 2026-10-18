<script lang="ts">
	import type { RoleRow, ScholarID, VolunteerRow } from '$data/types';
	import Button from '#lib/components/Button.svelte';
	import EditableText from '#lib/components/EditableText.svelte';
	import Feedback from '#lib/components/Feedback.svelte';
	import Paragraph from '#lib/components/Paragraph.svelte';
	import { getDB } from '#lib/data/CRUD.js';
	import { getLocaleContext } from '$routes/Contexts';
	import { handle } from '$routes/feedback.svelte';

	let {
		role,
		scholar,
		volunteer,
		active = undefined
	}: {
		role: RoleRow;
		scholar: ScholarID;
		volunteer: VolunteerRow | undefined;
		/** The volunteer's active assignments in this role, as editors count them; omitted
		 * where the count was not loaded. */
		active?: number | undefined;
	} = $props();

	const db = getDB();
	const locale = getLocaleContext();
</script>

{#if !role.invited && volunteer === undefined}
	<Button
		testid="volunteer-for-role"
		strings={(l) => l.view.roles.button.volunteer}
		action={() => handle(db().createVolunteer(scholar, scholar, role.id, true, true, null))}
		>Volunteer …</Button
	>
{/if}
{#if volunteer !== undefined}
	{#if volunteer.accepted === 'declined'}
		<p>
			{locale().view.roles.paragraph.declined}
			<Button
				strings={(l) => l.view.roles.button.accept}
				action={() => handle(db().acceptRoleInvite(volunteer.scholarid, volunteer.id, 'accepted'))}
				>Accept</Button
			>
		</p>
	{:else if volunteer.accepted === 'invited' && !volunteer.active}
		<Paragraph text={(l) => l.view.roles.paragraph.invited} />
		<Button
			testid="volunteer-accept-invite"
			strings={(l) => l.view.roles.button.acceptInvite}
			action={() => handle(db().acceptRoleInvite(volunteer.scholarid, volunteer.id, 'accepted'))}
			>Accept</Button
		>
		<Button
			testid="volunteer-decline-invite"
			strings={(l) => l.view.roles.button.decline}
			action={() => handle(db().acceptRoleInvite(volunteer.scholarid, volunteer.id, 'declined'))}
			>Decline</Button
		>
	{:else if volunteer.active}
		<p>
			{locale().view.roles.paragraph.volunteering}
			<Button
				testid="volunteered-for-role"
				strings={(l) => l.view.roles.button.stop}
				action={() => handle(db().updateVolunteerActive(volunteer.id, false))}>Stop...</Button
			>
		</p>
		<EditableText
			text={volunteer.expertise}
			strings={(l) => l.view.roles.field.expertise}
			edit={(text) => db().updateVolunteerExpertise(volunteer.id, text)}
			testid="volunteer-expertise"
		/>
		<EditableText
			text={volunteer.papers === null ? '' : volunteer.papers.toString()}
			strings={(l) => l.view.roles.field.papers}
			valid={(text) =>
				text === '' || /^\d+$/.test(text) ? undefined : (l) => l.view.roles.field.papers.invalid}
			edit={(text) =>
				db().updateVolunteerPapers(volunteer.id, text === '' ? null : parseInt(text, 10))}
			testid="volunteer-papers"
		/>
		<!-- What editors see when they choose reviewers, and the one thing RR cannot know on
		     its own: invitations accepted in the venue's reviewing system but never recorded
		     here. Only the volunteer can correct for those, so this asks them to. -->
		{#if active !== undefined}
			<div class="load" data-testid="volunteer-load">
				{#if volunteer.papers === null}
					<Paragraph
						text={(l) => l.view.roles.paragraph.loadNoCap}
						inputs={{ used: active.toString() }}
					/>
				{:else if active >= volunteer.papers}
					<!-- The same warning, styled the same way, as the one editors see about this
					     volunteer: being at the cap means the same thing on both sides. -->
					<Feedback
						warning
						testid="volunteer-at-cap"
						text={(l) => `${l.view.roles.paragraph.loadAtCap} ${l.view.roles.paragraph.loadNote}`}
						inputs={{ used: active.toString(), cap: volunteer.papers.toString() }}
					/>
				{:else}
					<Paragraph
						text={(l) => l.view.roles.paragraph.load}
						inputs={{ used: active.toString(), cap: volunteer.papers.toString() }}
					/>
				{/if}
				{#if volunteer.papers === null || active < volunteer.papers}
					<Paragraph text={(l) => l.view.roles.paragraph.loadNote} />
				{/if}
			</div>
		{/if}
	{:else}
		<p>
			{locale().view.roles.paragraph.stopped}
			<Button
				strings={(l) => l.view.roles.button.resume}
				testid="volunteer-resume"
				action={() => handle(db().updateVolunteerActive(volunteer.id, true))}>Resume...</Button
			>
		</p>
	{/if}
{/if}
