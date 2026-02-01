<script lang="ts">
	import type {
		CurrencyRow,
		RoleID,
		RoleRow,
		ScholarID,
		ScholarRow,
		VenueRow,
		VolunteerRow
	} from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Card from '$lib/components/Card.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { DeleteLabel, EmptyLabel, ScholarLabel } from '$lib/components/Labels';
	import Slider from '$lib/components/Slider.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { validEmail, isntEmpty, validEmailsOrORCIDs, validORCID } from '$lib/validation';
	import { handle } from '../../feedback.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Form from '$lib/components/Form.svelte';
	import Link from '$lib/components/Link.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import CurrencyLink from '$lib/components/CurrencyLink.svelte';
	import Options from '$lib/components/Options.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';

	let {
		venue,
		roles,
		volunteers,
		scholar,
		isAdmin,
		currency,
		minters
	}: {
		venue: VenueRow;
		scholar: ScholarID | undefined;
		roles: RoleRow[] | null;
		volunteers: VolunteerRow[] | null;
		isAdmin: boolean;
		currency: CurrencyRow;
		minters: ScholarRow[] | null;
	} = $props();

	const db = getDB();

	let newRole: string = $state('');
	let invites = $state<Record<RoleID, string>>(
		// svelte-ignore state_referenced_locally
		Object.fromEntries((roles ?? []).map((role) => [role.id, '']))
	);

	let newEditor: string = $state('');

	function validAdmin(scholar: string | ScholarID): string | undefined {
		if (validEmail(scholar)) {
			if (!(minters ?? []).some((m) => m.email === scholar)) return undefined;
			else return "Admins can't be minters of the venue's currency.";
		}
		if (validORCID(scholar)) {
			if (currency.minters.includes(scholar))
				return "Admins can't be minters of the venue's currency.";
			else return undefined;
		}
		return 'Must be a valid email or ORCID.';
	}
</script>

{#if roles}
	{#if isAdmin}
		<form>
			<p>Create a new role.</p>
			<TextField
				label="Role name"
				bind:text={newRole}
				size={19}
				placeholder="name"
				valid={(text) => (isntEmpty(text) ? undefined : 'Must include a name')}
			/><Button
				tip="Create a new role"
				active={isntEmpty(newRole)}
				action={async () => {
					const result = await handle(db().createRole(venue.id, newRole));
					if (typeof result !== 'boolean') {
						// Initialize the invite list for this role
						invites[result.id] = '';
						newRole = '';
					}
				}}>Create role</Button
			>
		</form>
	{/if}

	<Cards>
		<Card
			icon={venue.admins.length}
			subheader
			header="Admins"
			note="Scholars who manage this venue's configuration."
			expand={!isAdmin}
		>
			<p>
				This venue is administered by
				{#each venue.admins as adminID, index}
					{#if index > 0 && venue.admins.length > 1},{/if}
					{#if index === venue.admins.length - 1}and{/if}
					<ScholarLink id={adminID} />{#if isAdmin && venue.admins.length > 1}
						&nbsp;<Button
							tip="Remove admin"
							active={venue.admins.length > 1}
							warn="Are you sure you want to remove this admin?"
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
						label="Scholar"
						bind:text={newEditor}
						size={19}
						placeholder="ORCID or email"
						valid={(text) => validAdmin(text)}
					/><Button
						tip="Add admin"
						active={validAdmin(newEditor) === undefined}
						action={async () => {
							if (await handle(db().addVenueAdmin(venue.id, newEditor))) newEditor = '';
						}}>Add admin</Button
					>
				</form>
			{/if}
		</Card>
		{#each roles.toSorted((a, b) => a.priority - b.priority) as role, index (role.id)}
			{@const roleVolunteers = volunteers?.filter((v) => v.roleid === role.id) ?? []}
			<Card
				full
				subheader
				icon={roleVolunteers.length === 0 ? ScholarLabel : roleVolunteers.length}
				header={role.name}
				note={role.description.length === 0 ? 'Role' : role.description}
				expand={!isAdmin}
			>
				{#snippet controls()}
					{#if isAdmin}
						<Button
							active={index > 0}
							tip="Move this role's priority up"
							action={() => handle(db().reorderRole(role, $state.snapshot(roles), -1))}>↑</Button
						>
						<Button
							active={index < roles.length - 1}
							tip="Move this role's priority down"
							action={() => handle(db().reorderRole(role, $state.snapshot(roles), 1))}>↓</Button
						>
					{/if}
				{/snippet}

				{#if role.priority === 0}
					<Feedback
						>Because this role is the highest priority, volunteers for this role are assigned the
						role for new submissions.
					</Feedback>
				{/if}

				{@const scholarVolunteer = roleVolunteers.find((v) => v.scholarid === scholar)}

				<p>
					This {#if role.invited}<strong>invite only</strong>{/if} role is compensated <Tokens
						amount={role.amount}
					></Tokens> per submission in the currency <CurrencyLink {currency} />. <Link
						to="/venue/{venue.id}/volunteers">{roleVolunteers.length ?? 0} scholars</Link
					> have volunteered for this role.
				</p>

				{#if scholar}
					{#if !role.invited && scholarVolunteer === undefined}
						<Button
							tip="Volunteer for this role"
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
									tip="accept this invitation"
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
									tip="Stop volunteering"
									action={() => handle(db().updateVolunteerActive(scholarVolunteer.id, false))}
									>Stop...</Button
								>
							</p>
							<EditableText
								text={scholarVolunteer.expertise}
								label="what is your expertise? (separated by commas)?"
								placeholder="topic, area, method, theory, etc."
								edit={(text) => db().updateVolunteerExpertise(scholarVolunteer.id, text)}
							/>
						{:else}
							<p>
								You stopped volunteering for this role. <Button
									tip="Resume volunteering"
									action={() => handle(db().updateVolunteerActive(scholarVolunteer.id, true))}
									>Resume...</Button
								>
							</p>
						{/if}
					{/if}
				{:else if !role.invited}
					<Feedback error inline><Link to="/login">Log in</Link> to volunteer.</Feedback>
				{/if}

				{#if isAdmin && scholar}
					<Form>
						<p>
							Add one or more people to invite to this role by email or ORCID, separated by commas.
						</p>
						<TextField
							label="email or orcid"
							placeholder=""
							name="email"
							size={20}
							valid={(text) =>
								text.trim() === '' || validEmailsOrORCIDs(text)
									? undefined
									: 'Must be a comma separated list of emails or ORCID'}
							bind:text={invites[role.id]}
						/>
						<Button
							tip="Invite people to this role"
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
						icon="⚙️"
						header="settings"
						note="Edit this role's settings"
						subheader
						group="admins"
					>
						{#if roleVolunteers.length > 0}
							<Feedback error
								>This role has <strong>{roleVolunteers.length} volunteers</strong>. We
								<strong>highly</strong> recommend that you communicate extensively with your community
								before changing any of the settings below, as they change the terms of volunteering.
							</Feedback>
						{/if}

						<EditableText
							text={role.name}
							label="name"
							placeholder="name"
							valid={(text) => (isntEmpty(text) ? undefined : 'Must include a name')}
							edit={(text) => db().editRoleName(role.id, text)}
						/>
						<EditableText
							text={role.description}
							label="description"
							placeholder="description"
							edit={(text) => db().editRoleDescription(role.id, text)}
						/>
						<Slider
							min={1}
							max={venue.welcome_amount}
							value={role.amount}
							step={1}
							label="compensation"
							change={(value) => handle(db().editRoleAmount(role.id, value))}
							><Tokens amount={role.amount}></Tokens>/submission</Slider
						>
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
							warn="Delete this role and all volunteers?"
							tip="Delete this role"
							active={roles.length > 1}
							action={() => handle(db().deleteRole(role.id))}
							>{#if roles.length > 1}Delete {DeleteLabel} …{:else}Can't delete the last role{/if}</Button
						>
					</Card>
				{/if}
			</Card>
		{:else}
			<Feedback>No roles yet. Add one.</Feedback>
		{/each}
	</Cards>
{:else}
	<Feedback error>Couldn't load venue's roles.</Feedback>
{/if}
