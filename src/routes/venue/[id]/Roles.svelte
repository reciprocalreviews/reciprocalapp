<script lang="ts">
	import type { RoleRow, VenueRow } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Card from '$lib/components/Card.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { DeleteLabel } from '$lib/components/Labels';
	import Note from '$lib/components/Note.svelte';
	import Slider from '$lib/components/Slider.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { validIdentifier } from '$lib/validation';
	import { handle } from '../../errors.svelte';
	import TextField from '$lib/components/TextField.svelte';

	let {
		editor,
		venue,
		roles
	}: {
		editor: boolean;
		venue: VenueRow;
		roles: RoleRow[] | null;
	} = $props();

	const db = getDB();

	let newRole: string = $state('');
</script>

{#if editor}
	<form>
		<TextField
			bind:text={newRole}
			size={19}
			placeholder="name"
			valid={(text) => validIdentifier(text)}
		/><Button
			tip="Create a new role"
			active={validIdentifier(newRole)}
			action={() => handle(db.createRole(venue.id, newRole))}>Create role</Button
		>
	</form>
{/if}
{#if roles}
	{#if editor}
		{#each roles as role (role.id)}
			<Card>
				<EditableText
					text={role.name}
					label="name"
					placeholder=""
					valid={validIdentifier}
					edit={(text) => db.editRoleName(role.id, text)}
				/>
				<EditableText
					text={role.description}
					label="description"
					placeholder=""
					edit={(text) => db.editRoleDescription(role.id, text)}
				/>
				<Checkbox on={role.invited} change={(on) => db.editRoleInvited(role.id, on)}
					>Invited <Note
						>{#if role.invited}Scholars can volunteer for this without permission{:else}Scholars
							must be invited to this role.{/if}</Note
					>
				</Checkbox>
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
					action={() => handle(db.deleteRole(role.id))}>{DeleteLabel} …</Button
				>
			</Card>
		{:else}
			<Feedback>No roles yet. Add one.</Feedback>
		{/each}
	{:else}
		{#each roles as role (role.id)}
			<div class="role">
				<div class="tags">
					<Tag>{role.name}</Tag>
					<Tokens amount={role.amount}></Tokens>/submission
				</div>
				{#if role.description.length > 0}
					<Note>{role.description}</Note>
				{/if}
			</div>
		{:else}
			<Feedback>This venue has no volunteer roles.</Feedback>
		{/each}
	{/if}
{:else}
	<Feedback error>Couldn't load venue's roles.</Feedback>
{/if}

<style>
	.role {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
	}
</style>
