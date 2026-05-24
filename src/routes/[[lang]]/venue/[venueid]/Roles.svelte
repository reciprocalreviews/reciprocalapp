<script lang="ts">
	import type {
		CompensationRow,
		CurrencyRow,
		RoleID,
		RoleRow,
		ScholarID,
		ScholarRow,
		SubmissionType,
		VenueRow,
		VolunteerRow
	} from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Card from '$lib/components/Card.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import { DeleteLabel, ScholarLabel } from '$lib/components/Labels';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Slider from '$lib/components/Slider.svelte';
	import Table from '$lib/components/Table.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { isntEmpty, validEmailsOrORCIDs } from '$lib/validation';
	import { getLocaleContext } from '$routes/Contexts';
	import { handle } from '$routes/feedback.svelte';
	import AdminsCard from './AdminsCard.svelte';
	import RoleSettings from './RoleSettings.svelte';
	import VolunteerStatus from './VolunteerStatus.svelte';

	let {
		venue,
		roles,
		volunteers,
		scholar,
		isAdmin,
		currency,
		minters,
		compensation,
		types
	}: {
		venue: VenueRow;
		scholar: ScholarID | undefined;
		roles: RoleRow[] | null;
		volunteers: VolunteerRow[] | null;
		isAdmin: boolean;
		currency: CurrencyRow;
		minters: ScholarRow[] | null;
		types: SubmissionType[] | null;
		compensation: CompensationRow[] | null;
	} = $props();

	const db = getDB();
	const locale = getLocaleContext();

	let newRole: string = $state('');
	let invites = $state<Record<RoleID, string>>(
		// svelte-ignore state_referenced_locally
		Object.fromEntries((roles ?? []).map((role) => [role.id, '']))
	);
</script>

{#if roles === null}
	<Feedback error text={(l) => l.view.roles.feedback.notLoaded}></Feedback>
{:else}
	{#if isAdmin}
		<Form>
			<Paragraph text={(l) => l.view.roles.paragraph.createRole} />
			<TextField
				testid="new-role-name"
				strings={(l) => l.view.roles.field.newRoleName}
				bind:text={newRole}
				size={19}
				valid={(text) =>
					isntEmpty(text) ? undefined : (l) => l.view.roles.field.newRoleName.invalid ?? ''}
			/><Button
				strings={(l) => l.view.roles.button.createRole}
				testid="create-role-button"
				active={isntEmpty(newRole)}
				action={async () => {
					const result = await handle(db().createRole(venue.id, newRole));
					if (typeof result !== 'boolean') {
						// Initialize the invite list for this role
						invites[result.id] = '';
						newRole = '';
					}
				}}
			/>
		</Form>
	{/if}

	<Cards>
		{#each roles.toSorted((a, b) => a.priority - b.priority) as role, index (role.id)}
			{@const roleVolunteers = volunteers?.filter((v) => v.roleid === role.id) ?? []}
			{@const scholarVolunteer = roleVolunteers.find((v) => v.scholarid === scholar)}
			{@const scholarInvited =
				scholarVolunteer?.accepted === 'invited' && !scholarVolunteer.active}
			<Card
				full
				subheader
				icon={roleVolunteers.length === 0 ? ScholarLabel : roleVolunteers.length}
				strings={(l) => {
					return {
						header: role.name,
						note: role.description.length === 0 ? l.view.roles.card.unnamed : role.description
					};
				}}
				expand={isAdmin || !role.invited || scholarInvited}
				testid="role-{role.name}"
			>
				{#snippet controls()}
					{#if isAdmin}
						<Button
							active={index > 0}
							strings={(l) => l.view.roles.button.priorityUp}
							action={() => handle(db().reorderRole(role, $state.snapshot(roles), -1))}>↑</Button
						>
						<Button
							active={index < roles.length - 1}
							strings={(l) => l.view.roles.button.priorityDown}
							action={() => handle(db().reorderRole(role, $state.snapshot(roles), 1))}>↓</Button
						>
					{/if}
				{/snippet}

				{#if isAdmin && role.priority === 0}
					<Tip>{locale().view.roles.tip.highestPriority}</Tip>
				{/if}

				<Paragraph
					text={role.invited
						? (l) => l.view.roles.paragraph.roleInvited
						: (l) => l.view.roles.paragraph.roleOpen}
				/>

				<Table>
					{#snippet header()}
						<th style="width: 20%">{locale().view.roles.headers.type}</th>
						<th style="width: 40%">{locale().view.roles.headers.compensation}</th>
						<th style="width: 40%">{locale().view.roles.headers.rationale}</th>
					{/snippet}
					{#each types as type}
						{@const comp = compensation?.find(
							(c) => c.role === role.id && c.submission_type === type.id
						)}
						<tr>
							<td style="width: 20%">{type.name}</td>
							<td style="width: 40%">
								{#if isAdmin}
									{#if comp === undefined || comp.amount === null}
										<Button
											small
											strings={(l) => l.view.roles.button.addCompensation}
											action={async () =>
												handle(db().editCompensation(type.id, role.id, 1, comp?.rationale ?? ''))}
											>Add compensation</Button
										>
									{:else}
										<Slider
											min={1}
											max={venue.welcome_amount}
											value={comp.amount}
											step={1}
											immediately={false}
											strings={(l) => l.view.roles.slider.compensation}
											change={(value) =>
												handle(db().editCompensation(type.id, role.id, value, comp.rationale))}
											testid="compensation-{role.name}-{type.name}"
										/>
										<Button
											small
											strings={(l) => l.view.roles.button.removeCompensation}
											action={async () =>
												handle(db().editCompensation(type.id, role.id, null, comp.rationale))}
											>{DeleteLabel}</Button
										>
									{/if}
								{:else if comp === undefined || comp.amount === null}
									no role
								{:else}
									<Tokens amount={comp.amount} />
								{/if}
							</td>
							<td style="width: 40%">
								{#if comp && comp.amount !== null}
									{#if isAdmin}
										<EditableText
											text={comp.rationale}
											strings={(l) => l.view.roles.field.compensationRationale}
											edit={(text) => db().editCompensation(type.id, role.id, comp.amount, text)}
										/>
									{:else}
										{comp.rationale}
									{/if}
								{:else}—{/if}
							</td>
						</tr>
					{/each}
				</Table>

				<Paragraph
					text={(l) => l.view.roles.paragraph.volunteersCount}
					inputs={{ count: (roleVolunteers.length ?? 0).toString(), venueid: venue.id }}
				/>

				{#if scholar}
					<VolunteerStatus {role} {scholar} volunteer={scholarVolunteer} />
				{:else if !role.invited}
					<Feedback error inline text={(l) => l.view.roles.feedback.notInvited}></Feedback>
				{/if}

				{#if isAdmin && scholar}
					<Form>
						<Paragraph text={(l) => l.view.roles.paragraph.inviteDescription} />
						<TextField
							strings={(l) => l.view.roles.field.invite}
							name="email"
							size={20}
							valid={(text) =>
								text.trim() === '' || validEmailsOrORCIDs(text)
									? undefined
									: (l) => l.view.roles.field.invite.invalid ?? ''}
							bind:text={invites[role.id]}
							testid="role-invite-field-{role.name}"
						/>
						<Button
							strings={(l) => l.view.roles.button.invite}
							testid="role-invite-button-{role.name}"
							active={validEmailsOrORCIDs(invites[role.id])}
							action={async () => {
								if (
									await handle(
										db().inviteToRole(
											scholar,
											role,
											venue,
											invites[role.id].split(',').map((s) => s.trim())
										),
										'Invitations sent!'
									)
								)
									invites[role.id] = '';
							}}>Invite</Button
						>
					</Form>
				{/if}

				{#if isAdmin}
					<RoleSettings {role} {roles} volunteerCount={roleVolunteers.length} />
				{/if}
			</Card>
		{:else}
			<Feedback text={(l) => l.view.roles.feedback.noRoles}></Feedback>
		{/each}
		<AdminsCard {venue} {isAdmin} {minters} {currency} />
	</Cards>
{/if}
