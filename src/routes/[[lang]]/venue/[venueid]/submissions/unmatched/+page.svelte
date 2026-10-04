<script lang="ts">
	import type { RoleRow, UnmatchedAssignmentRow } from '$data/types';
	import Button from '#lib/components/Button.svelte';
	import Feedback from '#lib/components/Feedback.svelte';
	import Note from '#lib/components/Note.svelte';
	import Options from '#lib/components/Options.svelte';
	import Page from '#lib/components/Page.svelte';
	import Row from '#lib/components/Row.svelte';
	import Table from '#lib/components/Table.svelte';
	import { getDB } from '#lib/data/CRUD.js';
	import { matchPersonName, type Candidate } from '#lib/data/matchPersonName.js';
	import Text from '#lib/locales/Text.svelte';
	import { addFeedback, handle } from '$routes/feedback.svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import { type PageData } from './$types';

	/** Assignments an import could not match to a scholar, grouped by the name and role the
	 * file gave them, so all of one person's assignments are matched at once. Matching is
	 * by hand on purpose: a name is not an identity, and the wrong person in an editor role
	 * can approve and pay for work on the paper. Each viewer sees only the rows they could
	 * approve, which RLS decides. */
	let { data }: { data: PageData } = $props();
	const { venue, unmatched, roles, commitments } = $derived(data);

	const db = getDB();
	const locale = getLocaleContext();

	type Group = { key: string; name: string; role: RoleRow; rows: UnmatchedAssignmentRow[] };

	const groups = $derived.by(() => {
		const byKey = new Map<string, Group>();
		for (const row of unmatched ?? []) {
			const role = roles.find((r) => r.id === row.role);
			if (role === undefined) continue;
			const key = `${row.role}\u0000${row.name}`;
			const group = byKey.get(key) ?? { key, name: row.name, role, rows: [] };
			group.rows.push(row);
			byKey.set(key, group);
		}
		return [...byKey.values()].sort(
			(a, b) => a.role.priority - b.role.priority || a.name.localeCompare(b.name)
		);
	});

	/** Who may be matched in a role: its accepted, active volunteers, the rule the
	 * database enforces. */
	function candidatesFor(role: RoleRow): Candidate[] {
		return commitments
			.filter((c) => c.roleid === role.id && c.active && c.accepted === 'accepted')
			.map((c) => ({ id: c.scholarid, name: c.scholars?.name ?? '' }))
			.filter((c) => c.name.length > 0);
	}

	/** The viewer's pick per group, defaulting to a confident name match. */
	let choices = $state<Record<string, string | undefined>>({});
	function choiceFor(group: Group): string | undefined {
		if (group.key in choices) return choices[group.key];
		const match = matchPersonName(group.name, candidatesFor(group.role));
		return match.status === 'resolved' ? match.id : undefined;
	}

	async function match(group: Group, scholar: string) {
		if (venue === null) return;
		const result = await handle(
			db().matchAssignments(venue.id, group.name, group.role.id, scholar)
		);
		if (typeof result !== 'object') return;
		const who = candidatesFor(group.role).find((c) => c.id === scholar)?.name ?? group.name;
		const text = locale().page.unmatched.feedback;
		const matched = (result.matched.length === 1 ? text.matchedOne : text.matchedMany)
			.replaceAll('{name}', who)
			.replaceAll('{count}', result.matched.length.toString());
		addFeedback(
			result.skipped > 0
				? `${matched} ${text.skipped.replaceAll('{skipped}', result.skipped.toString())}`
				: matched,
			'success'
		);
	}

	async function dismiss(group: Group) {
		for (const row of group.rows) await handle(db().dismissUnmatchedAssignment(row.id));
	}
</script>

<Page band={false} title={(l) => l.page.unmatched.title}>
	<Note path={(l) => l.page.unmatched.note} />
	{#if groups.length === 0}
		<Feedback testid="unmatched-empty" text={(l) => l.page.unmatched.empty} />
	{:else}
		<Table full>
			{#snippet header()}
				<th><Text path={(l) => l.page.unmatched.headers.name} /></th>
				<th><Text path={(l) => l.page.unmatched.headers.role} /></th>
				<th><Text path={(l) => l.page.unmatched.headers.count} /></th>
				<th><Text path={(l) => l.page.unmatched.headers.scholar} /></th>
			{/snippet}
			{#each groups as group, index (group.key)}
				{@const candidates = candidatesFor(group.role)}
				{@const chosen = choiceFor(group)}
				<tr data-testid="unmatched-{index}">
					<td class="name">{group.name}</td>
					<td class="name">{group.role.name}</td>
					<td>{group.rows.length}</td>
					<td>
						<Row>
							{#if candidates.length === 0}
								<Feedback
									text={(l) => l.page.unmatched.noCandidates.replaceAll('{role}', group.role.name)}
								/>
							{:else}
								<Options
									testid="unmatched-{index}-scholar"
									value={chosen}
									options={[
										{ label: locale().page.unmatched.choose, value: undefined },
										...candidates.map((c) => ({ label: c.name, value: c.id }))
									]}
									onChange={(value) => (choices[group.key] = value)}
								/>
								<Button
									testid="unmatched-{index}-match"
									strings={(l) => l.page.unmatched.button.match}
									active={chosen !== undefined}
									action={() => (chosen === undefined ? undefined : match(group, chosen))}
								/>
							{/if}
							<Button
								testid="unmatched-{index}-dismiss"
								strings={(l) => l.page.unmatched.button.dismiss}
								action={() => dismiss(group)}
							/>
						</Row>
					</td>
				</tr>
			{/each}
		</Table>
	{/if}
</Page>

<style>
	/* A name or a role wrapping onto two lines reads as two different people. */
	.name {
		white-space: nowrap;
	}
</style>
