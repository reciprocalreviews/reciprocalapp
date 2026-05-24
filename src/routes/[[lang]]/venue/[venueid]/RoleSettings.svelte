<script lang="ts">
	import type { RoleID, RoleRow } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Card from '$lib/components/Card.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { DeleteLabel, SettingsLabel } from '$lib/components/Labels';
	import Options from '$lib/components/Options.svelte';
	import Slider from '$lib/components/Slider.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { getLocaleContext } from '$routes/Contexts';
	import { handle } from '$routes/feedback.svelte';
	import { isntEmpty } from '$lib/validation';

	let {
		role,
		roles,
		volunteerCount
	}: {
		role: RoleRow;
		roles: RoleRow[];
		volunteerCount: number;
	} = $props();

	const db = getDB();
	const locale = getLocaleContext();
</script>

<Card
	icon={SettingsLabel}
	strings={(l) => l.view.roles.card.settings}
	subheader
	group="admin"
	testid="role-settings-{role.name}"
>
	{#if volunteerCount > 0}
		<Feedback
			error
			text={(l) =>
				l.view.roles.feedback.consult.replace('{count}', volunteerCount.toString())}
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
		testid="role-description-{role.name}"
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
			role.biddable ? l.view.roles.checkbox.biddable.on : l.view.roles.checkbox.biddable.off}
		testid="role-biddable-{role.name}"
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
			...roles.filter((r) => r.id !== role.id).map((r) => ({ label: r.name, value: r.id }))
		]}
		onChange={(value) =>
			db().editRoleApprover(role.id, value === null ? null : (value as RoleID))}
	/>

	<Button
		strings={(l) => l.view.roles.button.deleteRole}
		testid="role-delete-{role.name}"
		active={roles.length > 1}
		action={() => handle(db().deleteRole(role.id))}
		>{#if roles.length > 1}Delete {DeleteLabel} …{:else}Can't delete the last role{/if}</Button
	>
</Card>
