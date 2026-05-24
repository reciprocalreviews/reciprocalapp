<script lang="ts">
	import type { RoleRow, ScholarID, VolunteerRow } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { getLocaleContext } from '$routes/Contexts';
	import { handle } from '$routes/feedback.svelte';

	let {
		role,
		scholar,
		volunteer
	}: {
		role: RoleRow;
		scholar: ScholarID;
		volunteer: VolunteerRow | undefined;
	} = $props();

	const db = getDB();
	const locale = getLocaleContext();
</script>

{#if !role.invited && volunteer === undefined}
	<Button
		testid="volunteer-for-role"
		strings={(l) => l.view.roles.button.volunteer}
		action={() =>
			handle(
				db().createVolunteer(scholar, scholar, role.id, true, true, null),
				"Thank you for volunteering! You'll receive your welcome tokens once the minter approves them."
			)}>Volunteer …</Button
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
