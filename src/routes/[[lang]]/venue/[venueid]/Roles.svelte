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
	import Checkbox from '$lib/components/Checkbox.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { DeleteLabel, EmptyLabel, ScholarLabel, SettingsLabel } from '$lib/components/Labels';
	import Slider from '$lib/components/Slider.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { validEmail, isntEmpty, validEmailsOrORCIDs, validORCID } from '$lib/validation';
	import type { LocaleText } from '$lib/locales/Locale';
	import { handle } from '$routes/feedback.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Form from '$lib/components/Form.svelte';
	import Link from '$lib/components/Link.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import CurrencyLink from '$lib/components/CurrencyLink.svelte';
	import Options from '$lib/components/Options.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Table from '$lib/components/Table.svelte';
	import Tip from '$lib/components/Tip.svelte';

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
		<form>
			<p>Create a new role.</p>
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
		</form>
	{/if}

	{@const admins = venue.admins}

	<Cards>
		<Card
			icon={venue.admins.length}
			subheader
			strings={(l) => l.view.roles.card.admins}
			expand={!isAdmin}
		>
			<p>
				This venue is administered by
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
			<p>
				Admins can edit venue information, add and remove other admins, and gift tokens. They are
				typically Editors-in-Chief, Program Chairs of a conference, or editorial staff.
			</p>

			{#if isAdmin}
				<form>
					<p>Add a new admin.</p>
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
				</form>
			{/if}
		</Card>
		{#each roles.toSorted((a, b) => a.priority - b.priority) as role, index (role.id)}
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
				expand={!isAdmin}
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

				{#if role.priority === 0}
					<Tip
						>This is the highest priority role. Any volunteers for this role are automatically
						assigned this role for new submissions.
					</Tip>
				{/if}

				{@const scholarVolunteer = roleVolunteers.find((v) => v.scholarid === scholar)}

				<p>
					This {#if role.invited}<strong>invite only</strong>{/if} role is compensated in <CurrencyLink
						{currency}
					/> as follows:
				</p>

				<Table>
					{#snippet header()}
						<th style="width: 20%">Type</th>
						<th style="width: 40%">Compensation</th>
						<th style="width: 40%">Rationale</th>
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
											change={(value) =>
												handle(db().editCompensation(type.id, role.id, value, comp.rationale))}
											><Tokens amount={comp.amount}></Tokens>/submission</Slider
										>
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
				<p>
					<Link to="/venue/{venue.id}/volunteers">{roleVolunteers.length ?? 0} scholars</Link> have volunteered
					for this role.
				</p>

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
								You declined this role. Would you like to accept it?
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
								Thanks for volunteering for this role! <Button
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
								You stopped volunteering for this role. <Button
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
						<p>
							Add one or more people to invite to this role by email or ORCID, separated by commas.
						</p>
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
						<Checkbox on={role.invited} change={(on) => db().editRoleInvited(role.id, on)}
							>{#if role.invited}Scholars must be invited to this role{:else}Scholars can volunteer
								for this role without being invited{/if}
						</Checkbox>

						<Checkbox
							on={role.anonymous_authors}
							change={(on) => db().editRoleAnonymousAuthors(role.id, on)}
							>{#if role.anonymous_authors}This role cannot see author information.{:else}This role
								can see author information.{/if}
						</Checkbox>

						<Checkbox on={role.biddable} change={(on) => db().editRoleBidding(role.id, on)}
							>{#if role.biddable}Volunteers can bid on submissions.{:else}Volunteers cannot bid for
								this role on submissions.{/if}
						</Checkbox>

						<Slider
							min={1}
							max={10}
							value={role.desired_assignments}
							step={1}
							label="What is the desired number of assignments for this role? If bidding is on, it will be turned off for a submission that has this number of
							assignments, to avoid unnecessary bids."
							immediately={false}
							change={(value) => handle(db().editRoleDesiredAssignments(role.id, value))}
							>{role.desired_assignments} assignments</Slider
						>

						<Options
							label="What role can approve assignments to this role for a submission, other than the editor?"
							value={role.approver ?? undefined}
							options={[
								{ label: EmptyLabel, value: undefined },
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
	</Cards>
{/if}
