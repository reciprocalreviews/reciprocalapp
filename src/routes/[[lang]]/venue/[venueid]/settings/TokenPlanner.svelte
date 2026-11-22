<script lang="ts">
	import type { CompensationRow, RoleRow, SubmissionType } from '#data/types.js';
	import EditableText from '#lib/components/EditableText.svelte';
	import Feedback from '#lib/components/Feedback.svelte';
	import Note from '#lib/components/Note.svelte';
	import Paragraph from '#lib/components/Paragraph.svelte';
	import Table from '#lib/components/Table.svelte';
	import Tokens from '#lib/components/Tokens.svelte';
	import tokenChip from '#lib/components/tokenChip.js';
	import type { Result } from '#lib/data/CRUD.js';
	import { getDB } from '#lib/data/CRUD.js';
	import { planFor } from '#lib/data/tokenPlan.js';
	import Text from '#lib/locales/Text.svelte';
	import { validInteger } from '#lib/validation.js';
	import { getLocaleContext } from '#routes/Contexts.js';

	/** The token planner (#57): for each submission type, what a paper pays out to its roles
	 * against what it costs, with every number editable in place. It edits the same
	 * columns as the role cards and the venue page's submission types, so the three stay in
	 * step through the page's normal reload after a write. It shows the balance and never
	 * refuses a save: see tokenPlan.ts for why. */
	let {
		roles,
		types,
		compensation
	}: {
		roles: RoleRow[];
		types: SubmissionType[];
		compensation: CompensationRow[];
	} = $props();

	const db = getDB();
	const locale = getLocaleContext();

	const plans = $derived(types.map((type) => ({ type, plan: planFor(type, roles, compensation) })));

	/** Nothing to write. Saving pay that didn't change would still email everyone in the role
	 * that their pay changed, so an unchanged value is not sent at all. */
	const unchanged: Result = { data: undefined };

	function savePay(type: SubmissionType, role: RoleRow, current: number | null, text: string) {
		const amount = text.trim() === '' ? null : parseInt(text);
		if (amount === current) return Promise.resolve(unchanged);
		const rationale =
			compensation.find((c) => c.role === role.id && c.submission_type === type.id)?.rationale ??
			'';
		return db().editCompensation(type.id, role.id, amount, rationale);
	}
</script>

<Paragraph text={(l) => l.page.settings.planner.hint} />

{#if types.length === 0}
	<Note path={(l) => l.page.settings.planner.noTypes} />
{:else if roles.length === 0}
	<Note path={(l) => l.page.settings.planner.noRoles} />
{:else}
	{#each plans as { type, plan } (type.id)}
		<section class="plan" data-testid="planner-{type.name}">
			<h3>{type.name}</h3>
			<Table>
				{#snippet header()}
					<th>{locale().page.settings.planner.headers.role}</th>
					<th>{locale().page.settings.planner.headers.count}</th>
					<th>{locale().page.settings.planner.headers.pay}</th>
					<th>{locale().page.settings.planner.headers.subtotal}</th>
				{/snippet}
				{#each plan.rows as row (row.role.id)}
					{@const role = roles.find((r) => r.id === row.role.id)}
					{#if role}
						<tr>
							<td>{role.name}</td>
							<td>
								<EditableText
									text={row.count.toString()}
									strings={(l) => l.page.settings.planner.field.count}
									valid={(text) =>
										validInteger(text) && parseInt(text) > 0
											? undefined
											: (l) => l.page.settings.planner.field.count.invalid ?? ''}
									edit={(text) =>
										parseInt(text) === row.count
											? Promise.resolve(unchanged)
											: db().editRoleDesiredAssignments(role.id, parseInt(text))}
									testid="planner-{type.name}-count-{role.name}"
								/>
							</td>
							<td>
								<EditableText
									text={row.amount === null ? '' : row.amount.toString()}
									strings={(l) => l.page.settings.planner.field.pay}
									valid={(text) =>
										text.trim() === '' || validInteger(text.trim())
											? undefined
											: (l) => l.page.settings.planner.field.pay.invalid ?? ''}
									edit={(text) => savePay(type, role, row.amount, text)}
									testid="planner-{type.name}-pay-{role.name}"
								/>
							</td>
							<td><Tokens amount={row.subtotal} /></td>
						</tr>
					{/if}
				{/each}
			</Table>

			<p>
				<Text
					markdown
					path={(l) => l.page.settings.planner.payout}
					inputs={{ payout: tokenChip(locale().widget.tokens, plan.payout) }}
				/>
			</p>

			<EditableText
				text={plan.cost.toString()}
				strings={(l) => l.page.settings.planner.field.cost}
				valid={(text) =>
					validInteger(text) ? undefined : (l) => l.page.settings.planner.field.cost.invalid ?? ''}
				edit={(text) =>
					parseInt(text) === plan.cost
						? Promise.resolve(unchanged)
						: db().editSubmissionTypeCost(type.id, parseInt(text))}
				testid="planner-{type.name}-cost"
			/>

			<Feedback
				inline={false}
				warning={plan.state === 'over'}
				text={(l) => l.page.settings.planner.status[plan.state]}
				inputs={{ difference: tokenChip(locale().widget.tokens, plan.difference) }}
				testid="planner-{type.name}-status"
			/>
		</section>
	{/each}

	<Note path={(l) => l.page.settings.planner.countNote} />
{/if}

<style>
	.plan {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--spacing-half);
		/* Stretched so the table has a width to lay out in: the page is a column flex
		   container that shrink-wraps its children. */
		align-self: stretch;
	}

	h3 {
		margin: 0;
	}

	/* Size the table to its content and let Table's wrapper scroll it when that's wider than
	   the page. Squeezed to fit, it wrapped a two-digit amount one digit per line on phones,
	   split token chips across lines, and let an open field's validation message spill over
	   the next column. At its content width, a message just widens its column. */
	.plan :global(.table) {
		max-width: 100%;
	}

	.plan :global(table) {
		width: max-content;
	}
</style>
