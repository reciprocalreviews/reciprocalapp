<script lang="ts">
	import type { RoleID, RoleRow, ScholarID, VenueRow, VolunteerRow } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Card from '$lib/components/Card.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { DeleteLabel } from '$lib/components/Labels';
	import Note from '$lib/components/Note.svelte';
	import Slider from '$lib/components/Slider.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { validEmail, isntEmpty, validEmails } from '$lib/validation';
	import { handle } from '../../feedback.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Form from '$lib/components/Form.svelte';
	import Link from '$lib/components/Link.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import { ORCIDRegex } from '../../../lib/data/ORCID';

	let {
		venue,
		roles,
		commitments,
		scholar,
		editor
	}: {
		venue: VenueRow;
		scholar: ScholarID | undefined;
		roles: RoleRow[] | null;
		commitments: VolunteerRow[] | null;
		editor: boolean;
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
			icon="👤"
			subheader
			header="Editor"
			note="Scholars who manage submissions and compensation fo this venue."
		>
			<p>
				Editors can edit venue information, add and remove other editors, create and archive
				submissions, and gift review tokens. They are typically Editors-in-Chief of a journal or
				Program Chairs of a conference.
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
							validEmail(text) || ORCIDRegex.test(text)
								? undefined
								: 'Must be a valid email or ORCID'}
					/><Button
						tip="Add editor"
						active={validEmail(newEditor) || ORCIDRegex.test(newEditor)}
						action={async () => {
							if (await handle(db.addVenueEditor(venue.id, newEditor))) newEditor = '';
						}}>Add editor</Button
					>
				</form>
			{:else}
				<p>Editors are compensated <Tokens amount={venue.edit_amount} /></p>
			{/if}
		</Card>
		{#each roles.toSorted((a, b) => a.priority - b.priority) as role, index (role.id)}
			<Card full subheader icon="👤" header={role.name} note={role.description}>
				{#snippet controls()}
					{#if editor}
						<Button
							active={index > 0}
							tip="Move this role up"
							action={() => handle(db.reorderRole(role, roles, -1))}>↑</Button
						>
						<Button
							active={index < roles.length - 1}
							tip="Move this role down"
							action={() => handle(db.reorderRole(role, roles, 1))}>↓</Button
						>
					{/if}
				{/snippet}

				{@const commitment = commitments?.find((c) => c.roleid === role.id)}

				<p>
					This {#if role.invited}<strong>invite only</strong>{/if} role is compensated <Tokens
						amount={role.amount}
					></Tokens> per submission.
				</p>

				{#if scholar}
					{#if role.invited}
						{#if commitment}
							{#if commitment.accepted === 'invited'}
								<p>
									The editor has invited you to take this role. <Button
										tip="accept this invitation"
										action={() => handle(db.acceptRoleInvite(commitment.id, 'accepted'))}
										>Accept</Button
									>
									<Button
										tip="decline this invitation"
										action={() => handle(db.acceptRoleInvite(commitment.id, 'declined'))}
										>Decline</Button
									>
								</p>
							{:else if commitment.accepted === 'declined'}
								<p>
									You declined this role. Would you like to accept it?
									<Button
										tip="accept this invitation"
										action={() => handle(db.acceptRoleInvite(commitment.id, 'accepted'))}
										>Accept</Button
									>
								</p>
							{/if}
						{:else}
							<Feedback error>This role is invite only.</Feedback>
						{/if}
					{:else if commitment === undefined}
						<Button
							tip="Volunteer for this role"
							action={() =>
								handle(
									db.createVolunteer(scholar, role.id, true, true),
									'Thank you for volunteering! The minter will approve your welcome tokens soon.'
								)}>Volunteer …</Button
						>
					{/if}
					{#if commitment}
						{#if commitment.active}
							<p>
								Thanks for volunteering for this role! <Button
									tip="Stop volunteering"
									action={() => handle(db.updateVolunteerActive(commitment.id, false))}
									>Stop...</Button
								>
							</p>
							<EditableText
								text={commitment.expertise}
								label="what is your expertise? (separated by commas)?"
								placeholder="topic, area, method, theory, etc."
								edit={(text) => db.updateVolunteerExpertise(commitment.id, text)}
							/>
						{:else}
							<p>
								You stopped volunteering for this role. <Button
									tip="Resume volunteering"
									action={() => handle(db.updateVolunteerActive(commitment.id, true))}
									>Resume...</Button
								>
							</p>
						{/if}
					{/if}
				{:else if !role.invited}
					<Feedback error inline>Log in to volunteer.</Feedback>
				{/if}

				{#if editor}
					<Form inline>
						<p>Add one or more people to invite to this role, separated by commas.</p>
						<TextField
							label="email"
							placeholder=""
							name="email"
							size={20}
							valid={(text) =>
								validEmails(text) ? undefined : 'Must a comma separated list of emails'}
							bind:text={invites[role.id]}
						/>
						<Button
							tip="Invite people to this role"
							active={validEmails(invites[role.id])}
							action={async () => {
								if (
									await handle(
										db.inviteToRole(
											role.id,
											invites[role.id].split(',').map((s) => s.trim())
										)
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
										? db.editRoleApprover(role.id, e.target.value === '' ? null : e.target.value)
										: null}
							>
								<option value={null}>—</option>
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
	<Card icon="+" header="add role" note="Create a new role" subheader group="editors">
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
					if (await handle(db.createRole(venue.id, newRole))) newRole = '';
				}}>Create role</Button
			>
		</form>
	</Card>
{/if}
