<script lang="ts">
	import type { RoleRow, VenueRow } from '$data/types';
	import Card from '$lib/components/Card.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Note from '$lib/components/Note.svelte';
	import Slider from '$lib/components/Slider.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { validIdentifier } from '$lib/validation';
	import { handle } from '../../errors.svelte';

	let {
		editor,
		venue,
		roles
	}: {
		editor: boolean;
		venue: VenueRow;
		roles: RoleRow[];
	} = $props();

	const db = getDB();
</script>

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
					>{#if role.invited}Scholars can volunteer for this without permission{:else}Scholars must
						be invited to this role.{/if}</Note
				>
			</Checkbox>
			<Slider
				min={1}
				max={venue.welcome_amount}
				value={role.amount}
				step={1}
				label="compensation"
				unit="tokens/submission"
				change={(value) => handle(db.editRoleAmount(role.id, value))}
			/>
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

<style>
	.role {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
	}
</style>
