<script lang="ts">
	import type { RoleID, RoleRow, VenueRow } from '$data/types';
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
	import { validEmail, isntEmpty } from '$lib/validation';
	import { handle } from '../../feedback.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Form from '$lib/components/Form.svelte';

	let {
		venue,
		roles
	}: {
		venue: VenueRow;
		roles: RoleRow[] | null;
	} = $props();

	const db = getDB();

	let newRole: string = $state('');
	let invites = $derived<Record<RoleID, string>>(
		Object.fromEntries((roles ?? []).map((role) => [role.id, '']))
	);
</script>

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
{#if roles}
	{#each roles.toSorted((a, b) => a.order - b.order) as role, index (role.id)}
		<Card subheader icon="👤" header={role.name} note={role.description}>
			{#snippet controls()}
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
			{/snippet}
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
			<Checkbox on={role.invited} change={(on) => db.editRoleInvited(role.id, on)}
				>Invited <Note
					>{#if role.invited}Scholars can volunteer for this without permission{:else}Scholars must
						be invited to this role.{/if}</Note
				>
			</Checkbox>
			<Checkbox on={role.biddable} change={(on) => db.editRoleBidding(role.id, on)}
				>Allow bidding
			</Checkbox>
			<Note
				>{#if role.biddable}Authenticated volunteers can bid to take this role on submissions.{:else}This
					role can only be set for a submission by editors.{/if}</Note
			>

			{#if role.invited}
				<Form inline>
					<p>Add one or more people to invite to this role, separated by commands.</p>
					<TextField
						label="email"
						placeholder=""
						name="email"
						size={20}
						valid={(text) => (validEmail(text) ? undefined : 'Must be a valid email')}
						bind:text={invites[role.id]}
					/>
					<Button
						tip="Invite people to this role"
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
			<Slider
				min={1}
				max={venue.welcome_amount}
				value={role.amount}
				step={1}
				label="compensation"
				change={(value) => handle(db.editRoleAmount(role.id, value))}
				><Tokens amount={role.amount}></Tokens>/submission</Slider
			>
			<Button
				warn="Delete this role and all volunteers?"
				tip="Delete this role"
				action={() => handle(db.deleteRole(role.id))}>Delete {DeleteLabel} …</Button
			>
		</Card>
	{:else}
		<Feedback>No roles yet. Add one.</Feedback>
	{/each}
{:else}
	<Feedback error>Couldn't load venue's roles.</Feedback>
{/if}
