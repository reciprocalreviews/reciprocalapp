<script lang="ts">
	import type {
		CurrencyRow,
		RoleID,
		RoleRow,
		ScholarID,
		VenueRow,
		VolunteerRow
	} from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Card from '$lib/components/Card.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { CreateLabel, DeleteLabel, EmptyLabel } from '$lib/components/Labels';
	import Note from '$lib/components/Note.svelte';
	import Slider from '$lib/components/Slider.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { validEmail, isntEmpty, validEmailsOrORCIDs, validORCID } from '$lib/validation';
	import { handle } from '../../feedback.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Form from '$lib/components/Form.svelte';
	import Link from '$lib/components/Link.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import CurrencyLink from '$lib/components/CurrencyLink.svelte';

	let {
		venue,
		roles,
		volunteers,
		scholar,
		editor,
		currency
	}: {
		venue: VenueRow;
		scholar: ScholarID | undefined;
		roles: RoleRow[] | null;
		volunteers: VolunteerRow[] | null;
		editor: boolean;
		currency: CurrencyRow;
	} = $props();

	const db = getDB();

	let newRole: string = $state('');
	let invites = $state<Record<RoleID, string>>(
		Object.fromEntries((roles ?? []).map((role) => [role.id, '']))
	);

	let newEditor: string = $state('');
</script>

{#if editor}
	<Tip>
		These are the roles that volunteers can commit to. Create roles such as <em>reviewer</em>,
		<em>program commitee</em>, <em>associate editor</em> to represent the different kinds of contributions
		volunteers can make to this venue.
	</Tip>
{/if}
<p>See <Link to="/venue/{venue.id}/volunteers">all volunteers</Link> for this venue.</p>

{#if roles}
	<Cards>
		<Card
			icon={venue.editors.length}
			subheader
			header="Editor"
			note="Scholars who manage submissions and compensation fo this venue."
		>
			<p>
				Editors can edit venue information, add and remove other editors, create and archive
				submissions, and gift review tokens. They are typically Editors-in-Chief of a journal or
				Program Chairs of a conference. Editors are compensated <Tokens
					amount={venue.edit_amount}
				/> per submission in the currency
				<CurrencyLink {currency} />.
			</p>

			{#if editor}
				<Slider
					min={1}
					max={venue.welcome_amount}
					value={venue.edit_amount}
					step={1}
					label="compensation"
					change={(value) => handle(db.editVenueEditorCompensation(venue.id, value))}
					><Tokens amount={venue.edit_amount}></Tokens>/submission</Slider
				>
				<form>
					<TextField
						bind:text={newEditor}
						size={19}
						placeholder="ORCID or email"
						valid={(text) =>
							validEmail(text) || validORCID(text) ? undefined : 'Must be a valid email or ORCID'}
					/><Button
						tip="Add editor"
						active={validEmail(newEditor) || validORCID(newEditor)}
						action={async () => {
							if (await handle(db.addVenueEditor(venue.id, newEditor))) newEditor = '';
						}}>Add editor</Button
					>
				</form>
			{/if}
		</Card>
		{#each roles.toSorted((a, b) => a.priority - b.priority) as role, index (role.id)}
			{@const roleVolunteers = volunteers?.filter((v) => v.roleid === role.id) ?? []}
			<Card
				full
				subheader
				icon={roleVolunteers.length === 0 ? '👤' : roleVolunteers.length}
				header={role.name}
				note={role.description.length === 0 ? 'Role' : role.description}
			>
				{#snippet controls()}
					{#if editor}
						<Button
							active={index > 0}
							tip="Move this role up"
							action={() => handle(db.reorderRole(role, $state.snapshot(roles), -1))}>↑</Button
						>
						<Button
							active={index < roles.length - 1}
							tip="Move this role down"
							action={() => handle(db.reorderRole(role, $state.snapshot(roles), 1))}>↓</Button
						>
					{/if}
				{/snippet}

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
									db.createVolunteer(scholar, scholar, role.id, true, true),
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
											db.acceptRoleInvite(
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
									action={() => handle(db.updateVolunteerActive(scholarVolunteer.id, false))}
									>Stop...</Button
								>
							</p>
							<EditableText
								text={scholarVolunteer.expertise}
								label="what is your expertise? (separated by commas)?"
								placeholder="topic, area, method, theory, etc."
								edit={(text) => db.updateVolunteerExpertise(scholarVolunteer.id, text)}
							/>
						{:else}
							<p>
								You stopped volunteering for this role. <Button
									tip="Resume volunteering"
									action={() => handle(db.updateVolunteerActive(scholarVolunteer.id, true))}
									>Resume...</Button
								>
							</p>
						{/if}
					{/if}
				{:else if !role.invited}
					<Feedback error inline>Log in to volunteer.</Feedback>
				{/if}

				{#if editor && scholar}
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
										db.inviteToRole(
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

				{#if editor}
					<Card
						icon="⚙️"
						header="settings"
						note="Edit this role's settings"
						subheader
						group="editors"
					>
						<EditableText
							text={role.name}
							label="name"
							placeholder="name"
							valid={(text) => (isntEmpty(text) ? undefined : 'Must include a name')}
							edit={(text) => db.editRoleName(role.id, text)}
						/>
						<EditableText
							text={role.description}
							label="description"
							placeholder="description"
							edit={(text) => db.editRoleDescription(role.id, text)}
						/>
						<Slider
							min={1}
							max={venue.welcome_amount}
							value={role.amount}
							step={1}
							label="compensation"
							change={(value) => handle(db.editRoleAmount(role.id, value))}
							><Tokens amount={role.amount}></Tokens>/submission</Slider
						>
						<Checkbox on={role.invited} change={(on) => db.editRoleInvited(role.id, on)}
							>Invited <Note
								>{#if role.invited}Scholars must be invited to this role.{:else}Scholars can
									volunteer for this without permission{/if}</Note
							>
						</Checkbox>
						<Checkbox on={role.biddable} change={(on) => db.editRoleBidding(role.id, on)}
							>Allow bidding
						</Checkbox>

						<label>
							What role can approve bids for this role, other than the editor?
							<select
								value={role.approver}
								onchange={(e) =>
									e.target instanceof HTMLSelectElement
										? db.editRoleApprover(role.id, e.target.value === null ? null : e.target.value)
										: null}
							>
								<option value={null}>{EmptyLabel}</option>
								{#each roles.filter((r) => r.id !== role.id) as otherRole}<option
										value={otherRole.id}>{otherRole.name}</option
									>{/each}</select
							>
						</label>

						<Note
							>{#if role.biddable}Authenticated volunteers can bid to take this role on submissions.{:else}This
								role can only be set for a submission by editors.{/if}</Note
						>

						<Button
							warn="Delete this role and all volunteers?"
							tip="Delete this role"
							action={() => handle(db.deleteRole(role.id))}>Delete {DeleteLabel} …</Button
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
{#if editor}
	<Card icon={CreateLabel} header="add role" note="Create a new role" subheader group="editors">
		<form>
			<TextField
				bind:text={newRole}
				size={19}
				placeholder="name"
				valid={(text) => (isntEmpty(text) ? undefined : 'Must include a name')}
			/><Button
				tip="Create a new role"
				active={isntEmpty(newRole)}
				action={async () => {
					const result = await handle(db.createRole(venue.id, newRole));
					if (typeof result !== 'boolean') {
						// Initialize the invite list for this role
						invites[result.id] = '';
						newRole = '';
					}
				}}>Create role</Button
			>
		</form>
	</Card>
{/if}
