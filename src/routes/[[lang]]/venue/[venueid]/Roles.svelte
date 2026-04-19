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
	import Checkbox from '$lib/components/Checkbox.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import { DeleteLabel, ScholarLabel, SettingsLabel } from '$lib/components/Labels';
	import Options from '$lib/components/Options.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Slider from '$lib/components/Slider.svelte';
	import Table from '$lib/components/Table.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import { getDB } from '$lib/data/CRUD';
	import type { LocaleText } from '$lib/locales/Locale';
	import { isntEmpty, validEmail, validEmailsOrORCIDs, validORCID } from '$lib/validation';
	import { getLocaleContext } from '$routes/Contexts';
	import { handle } from '$routes/feedback.svelte';

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

	let newEditor: string = $state('');

	function validAdmin(scholar: string | ScholarID): ((l: LocaleText) => string) | undefined {
		if (validEmail(scholar)) {
			if (!(minters ?? []).some((m) => m.email === scholar)) return undefined;
			else return (_l) => "Admins can't be minters of the venue's currency.";
		}
		if (validORCID(scholar)) {
			if (currency.minters.includes(scholar))
				return (_l) => "Admins can't be minters of the venue's currency.";
			else return undefined;
		}
		return (_l) => 'Must be a valid email or ORCID.';
	}
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

	{@const admins = venue.admins}

	<Cards>
		{#each roles.toSorted((a, b) => b.priority - a.priority) as role, index (role.id)}
			{@const roleVolunteers = volunteers?.filter((v) => v.roleid === role.id) ?? []}
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
				expand={isAdmin || !role.invited}
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

				{@const scholarVolunteer = roleVolunteers.find((v) => v.scholarid === scholar)}

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
					{#if !role.invited && scholarVolunteer === undefined}
						<Button
							strings={(l) => l.view.roles.button.volunteer}
							action={() =>
								handle(
									db().createVolunteer(scholar, scholar, role.id, true, true),
									"Thank you for volunteering! You'll receive your welcome tokens once the minter approves them."
								)}>Volunteer …</Button
						>
					{/if}
					{#if scholarVolunteer !== undefined}
						{#if scholarVolunteer.accepted === 'declined'}
							<p>
								{locale().view.roles.paragraph.declined}
								<Button
									strings={(l) => l.view.roles.button.accept}
									action={() =>
										handle(
											db().acceptRoleInvite(
												scholarVolunteer.scholarid,
												scholarVolunteer.id,
												'accepted'
											)
										)}>Accept</Button
								>
							</p>
						{:else if scholarVolunteer.active}
							<p>
								{locale().view.roles.paragraph.volunteering}
								<Button
									testid="volunteered-for-role"
									strings={(l) => l.view.roles.button.stop}
									action={() => handle(db().updateVolunteerActive(scholarVolunteer.id, false))}
									>Stop...</Button
								>
							</p>
							<EditableText
								text={scholarVolunteer.expertise}
								strings={(l) => l.view.roles.field.expertise}
								edit={(text) => db().updateVolunteerExpertise(scholarVolunteer.id, text)}
							/>
						{:else}
							<p>
								{locale().view.roles.paragraph.stopped}
								<Button
									strings={(l) => l.view.roles.button.resume}
									action={() => handle(db().updateVolunteerActive(scholarVolunteer.id, true))}
									>Resume...</Button
								>
							</p>
						{/if}
					{/if}
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
						/>
						<Button
							strings={(l) => l.view.roles.button.invite}
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
					<Card
						icon={SettingsLabel}
						strings={(l) => l.view.roles.card.settings}
						subheader
						group="admin"
					>
						{#if roleVolunteers.length > 0}
							<Feedback
								error
								text={(l) =>
									l.view.roles.feedback.consult.replace(
										'{count}',
										roleVolunteers.length.toString()
									)}
							/>
						{/if}

						<EditableText
							text={role.name}
							strings={(l) => l.view.roles.field.roleName}
							valid={(text) =>
								isntEmpty(text) ? undefined : (l) => l.view.roles.field.roleName.invalid ?? ''}
							edit={(text) => db().editRoleName(role.id, text)}
						/>
						<EditableText
							text={role.description}
							strings={(l) => l.view.roles.field.roleDescription}
							edit={(text) => db().editRoleDescription(role.id, text)}
						/>
						<Checkbox
							on={role.invited}
							change={(on) => db().editRoleInvited(role.id, on)}
							label={(l) =>
								role.invited ? l.view.roles.checkbox.invited.on : l.view.roles.checkbox.invited.off}
						/>

						<Checkbox
							on={role.anonymous_authors}
							change={(on) => db().editRoleAnonymousAuthors(role.id, on)}
							label={(l) =>
								role.anonymous_authors
									? l.view.roles.checkbox.anonymousAuthors.on
									: l.view.roles.checkbox.anonymousAuthors.off}
						/>

						<Checkbox
							on={role.biddable}
							change={(on) => db().editRoleBidding(role.id, on)}
							label={(l) =>
								role.biddable
									? l.view.roles.checkbox.biddable.on
									: l.view.roles.checkbox.biddable.off}
						/>

						<Slider
							min={1}
							max={10}
							value={role.desired_assignments}
							step={1}
							strings={(l) => l.view.roles.slider.desiredAssignments}
							immediately={false}
							change={(value) => handle(db().editRoleDesiredAssignments(role.id, value))}
						/>

						<Options
							strings={(l) => l.view.roles.options.approver}
							value={role.approver ?? undefined}
							options={[
								{ label: locale().shorthand.empty, value: undefined },
								...roles
									.filter((r) => r.id !== role.id)
									.map((r) => ({ label: r.name, value: r.id }))
							]}
							onChange={(value) =>
								db().editRoleApprover(role.id, value === null ? null : (value as RoleID))}
						/>

						<Button
							strings={(l) => l.view.roles.button.deleteRole}
							active={roles.length > 1}
							action={() => handle(db().deleteRole(role.id))}
							>{#if roles.length > 1}Delete {DeleteLabel} …{:else}Can't delete the last role{/if}</Button
						>
					</Card>
				{/if}
			</Card>
		{:else}
			<Feedback text={(l) => l.view.roles.feedback.noRoles}></Feedback>
		{/each}
		<Card
			icon={venue.admins.length}
			subheader
			strings={(l) => l.view.roles.card.admins}
			expand={isAdmin}
		>
			<p>
				{locale().view.roles.paragraph.administeredBy}
				{#each admins as adminID, index}
					{#if index > 0 && admins.length > 2},{/if}
					{#if index === admins.length - 1 && admins.length > 1}and{/if}
					<ScholarLink id={adminID} />{#if isAdmin && admins.length > 1}
						&nbsp;<Button
							strings={(l) => l.view.roles.button.removeAdmin}
							active={venue.admins.length > 1}
							action={() =>
								handle(
									db().editVenueAdmins(
										venue.id,
										venue.admins.filter((ad) => ad !== adminID)
									)
								)}>{DeleteLabel}</Button
						>{/if}
				{/each}.
			</p>
			<Paragraph text={(l) => l.view.roles.paragraph.adminsDescription} />

			{#if isAdmin}
				<Form>
					<Paragraph text={(l) => l.view.roles.paragraph.addAdmin} />
					<TextField
						strings={(l) => l.view.roles.field.adminScholar}
						bind:text={newEditor}
						size={19}
						valid={(text) => validAdmin(text)}
					/><Button
						strings={(l) => l.view.roles.button.addAdmin}
						active={validAdmin(newEditor) === undefined}
						action={async () => {
							if (await handle(db().addVenueAdmin(venue.id, newEditor))) newEditor = '';
						}}
					/>
				</Form>
			{/if}
		</Card>
	</Cards>
{/if}
