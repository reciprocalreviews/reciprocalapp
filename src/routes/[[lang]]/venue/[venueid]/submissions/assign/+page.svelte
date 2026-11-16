<script lang="ts">
	import Button from '#lib/components/Button.svelte';
	import Feedback from '#lib/components/Feedback.svelte';
	import Form from '#lib/components/Form.svelte';
	import Options from '#lib/components/Options.svelte';
	import Page from '#lib/components/Page.svelte';
	import Paragraph from '#lib/components/Paragraph.svelte';
	import ScholarLink from '#lib/components/ScholarLink.svelte';
	import Status from '#lib/components/Status.svelte';
	import SubmissionLink from '#lib/components/SubmissionLink.svelte';
	import Table from '#lib/components/Table.svelte';
	import TextField from '#lib/components/TextField.svelte';
	import VolunteerPicker from '#lib/components/VolunteerPicker.svelte';
	import {
		ProblemVerdicts,
		looksLikeEmail,
		parseAssignmentList,
		repeatedLines,
		resolveWho,
		toListAssignment
	} from '#lib/data/assignmentList.js';
	import {
		getDB,
		type AssignFromListResult,
		type ListAssignment,
		type ListAssignmentRow
	} from '#lib/data/CRUD.js';
	import Loads, { type Load } from '#lib/data/load.js';
	import { volunteersFor, type PersonMatch } from '#lib/data/matchPersonName.js';
	import { venueBarName } from '#lib/data/venueBarLinks.js';
	import type LocaleText from '#lib/locales/Locale.js';
	import Text from '#lib/locales/Text.svelte';
	import { handle } from '#routes/feedback.svelte.js';
	import { type PageData } from './$types';

	/** Seats people in one role on submissions the venue already has, from a list pasted
	 * from the reviewing system where those assignments were just made. Everything here is
	 * local state rather than page data, so a realtime refresh doesn't clear a list
	 * mid-check. */
	let { data }: { data: PageData } = $props();
	const { venue, roles, commitments, mayAssign } = $derived(data);

	const db = getDB();

	const sortedRoles = $derived(roles.toSorted((a, b) => a.priority - b.priority));

	let chosenRole = $state<string | undefined>(undefined);
	/** The top-priority role until another is chosen: the list this exists for is a round
	 * of editor assignments. */
	const role = $derived(sortedRoles.find((r) => r.id === chosenRole) ?? sortedRoles[0]);

	let text = $state('');
	const lines = $derived(parseAssignmentList(text));
	const candidates = $derived(role ? volunteersFor(commitments, role.id) : []);

	/** A volunteer the editor chose for an ambiguous or unmatched name, by role and then by
	 * line, kept apart from the text so the line stays as pasted. Keyed by role id rather
	 * than cleared when the role changes: a refresh of the page data rebuilds the role
	 * without changing it, and a choice must survive that. */
	let pinsByRole = $state<Record<string, Record<number, string>>>({});
	const pins = $derived(role ? (pinsByRole[role.id] ?? {}) : {});
	function setPins(next: Record<number, string>) {
		if (role) pinsByRole = { ...pinsByRole, [role.id]: next };
	}

	const matches = $derived(lines.map((line, i) => resolveWho(line.written, candidates, pins[i])));
	const repeated = $derived(repeatedLines(lines));

	/** What each line sends, or null for a line that sends nothing. Indexed like `lines`. */
	const sent = $derived(
		lines.map((line, i) => (repeated.has(i) ? null : toListAssignment(line, matches[i])))
	);
	const payload = $derived(sent.filter((s): s is ListAssignment => s !== null));
	/** Identifies the payload, so a check is known to be about exactly what is on screen. */
	const payloadKey = $derived(role ? JSON.stringify([role.id, payload]) : '');

	const unresolved = $derived(matches.some((m) => m.status === 'ambiguous'));

	/** The last check or assignment, and what it was made for. */
	let checked = $state<{ key: string; result: AssignFromListResult; final: boolean } | null>(null);
	const current = $derived(checked !== null && checked.key === payloadKey ? checked : null);
	const stale = $derived(checked !== null && !checked.final && checked.key !== payloadKey);

	/** The database's verdict for each line, by line index. */
	const verdicts = $derived.by(() => {
		const byLine = new Map<number, ListAssignmentRow>();
		if (current === null) return byLine;
		let next = 0;
		sent.forEach((s, i) => {
			if (s === null) return;
			const row = current.result.rows[next++];
			if (row !== undefined) byLine.set(i, row);
		});
		return byLine;
	});

	const counts = $derived.by(() => {
		const rows = current?.result.rows ?? [];
		return {
			ready: rows.filter((r) => r.verdict === 'ready').length,
			keep: rows.filter((r) => r.verdict === 'keep').length,
			problems:
				rows.filter((r) => ProblemVerdicts.has(r.verdict)).length +
				sent.filter((s) => s === null).length
		};
	});
	const actionable = $derived(counts.ready + counts.keep);

	/** How loaded each person this list seats already is, read once a check comes back. */
	let loads = $state<Loads | null>(null);

	/** Whether seating this line's person puts them past the cap they set for the role,
	 * counting every line of this list that seats them, since that is what confirming does. */
	const overCap = $derived.by(() => {
		const result = new Map<number, { load: Load; adding: number }>();
		const counted = loads;
		if (current === null || current.final || counted === null || !role) return result;
		const adding = new Map<string, number>();
		verdicts.forEach((v, i) => {
			const s = sent[i];
			if (v.verdict === 'ready' && s && 'person' in s)
				adding.set(s.person, (adding.get(s.person) ?? 0) + 1);
		});
		verdicts.forEach((v, i) => {
			const s = sent[i];
			if (v.verdict !== 'ready' || !s || !('person' in s)) return;
			const cap =
				commitments.find((c) => c.roleid === role.id && c.scholarid === s.person)?.papers ?? null;
			const load = counted.of(s.person, role.id, cap);
			const add = adding.get(s.person) ?? 0;
			if (load.cap !== null && load.used + add > load.cap) result.set(i, { load, adding: add });
		});
		return result;
	});

	async function check() {
		if (!venue || !role || payload.length === 0) return;
		const key = payloadKey;
		const result = await handle(db().assignFromList(venue.id, role.id, payload, true));
		if (typeof result !== 'object') return;
		checked = { key, result, final: false };
		const people = [...new Set(payload.flatMap((p) => ('person' in p ? [p.person] : [])))];
		const counted = await db().getAssignmentLoads(venue.id, people);
		loads = counted.data === null ? null : new Loads(counted.data);
	}

	async function assign() {
		if (!venue || !role || current === null) return;
		const key = payloadKey;
		const result = await handle(db().assignFromList(venue.id, role.id, payload, false));
		if (typeof result !== 'object') return;
		checked = { key, result, final: true };
	}

	function reset() {
		text = '';
		pinsByRole = {};
		checked = null;
		loads = null;
	}

	/** What a line's status cell says: the database's verdict when checked, otherwise why
	 * the line sends nothing, otherwise that it has not been checked. */
	function lineStatus(
		index: number,
		match: PersonMatch
	): { label: (l: LocaleText) => string; good: boolean; neutral: boolean } {
		const line = lines[index];
		const verdict = verdicts.get(index);
		if (line.externalID === '')
			return { label: (l) => l.page.assignList.local.noID, good: false, neutral: false };
		if (repeated.has(index))
			return { label: (l) => l.page.assignList.local.repeated, good: false, neutral: false };
		if (match.status === 'none')
			return { label: (l) => l.page.assignList.local.nobody, good: false, neutral: false };
		if (match.status === 'ambiguous')
			return { label: (l) => l.page.assignList.local.ambiguous, good: false, neutral: false };
		if (match.status === 'unmatched' && looksLikeEmail(line.written))
			return {
				label: (l) => l.page.assignList.local.emailUnmatched,
				good: false,
				neutral: false
			};
		if (verdict === undefined)
			return { label: (l) => l.page.assignList.local.unchecked, good: false, neutral: true };
		const v = verdict.verdict;
		return {
			label: (l) => l.page.assignList.verdict[v],
			good: v === 'ready' || v === 'seated',
			neutral: !ProblemVerdicts.has(v) && !(v === 'ready' || v === 'seated')
		};
	}
</script>

{#if venue === null}
	<Page title={(l) => l.page.assignList.title}>
		<Feedback error text={(l) => l.page.assignList.notLoaded} />
	</Page>
{:else}
	<Page title={(l) => l.page.assignList.title} context={venueBarName(venue)}>
		{#if !mayAssign}
			<Feedback error text={(l) => l.page.assignList.notAllowed} testid="assign-list-not-allowed" />
		{:else if role === undefined}
			<Feedback error text={(l) => l.page.assignList.notLoaded} />
		{:else}
			<Paragraph text={(l) => l.page.assignList.intro} />
			<Form>
				<Options
					strings={(l) => l.page.assignList.options.role}
					bind:value={chosenRole}
					options={sortedRoles.map((r) => ({ value: r.id, label: r.name }))}
					testid="assign-list-role"
				/>
				<!-- Capped, because the textarea grows to its content and a pasted list can
				     run to hundreds of lines. -->
				<div class="paste">
					<TextField
						strings={(l) => l.page.assignList.field.list}
						size={50}
						inline={false}
						testid="assign-list-text"
						bind:text
					/>
				</div>
				<Button
					strings={(l) => l.page.assignList.button.check}
					type="submit"
					active={payload.length > 0 && !unresolved && !(checked?.final && current !== null)}
					action={check}
					testid="assign-list-check"
				/>
			</Form>

			{#if unresolved}
				<Feedback
					warning
					text={(l) => l.page.assignList.unresolved}
					testid="assign-list-unresolved"
				/>
			{:else if stale}
				<Feedback warning text={(l) => l.page.assignList.stale} testid="assign-list-stale" />
			{/if}

			{#if lines.length > 0}
				<Table full>
					{#snippet header()}
						<th><Text path={(l) => l.page.assignList.headers.id} /></th>
						<th><Text path={(l) => l.page.assignList.headers.submission} /></th>
						<th><Text path={(l) => l.page.assignList.headers.who} /></th>
						<th><Text path={(l) => l.page.assignList.headers.status} /></th>
					{/snippet}
					{#each lines as line, index (index)}
						{@const match = matches[index]}
						{@const verdict = verdicts.get(index)}
						{@const status = lineStatus(index, match)}
						{@const cap = overCap.get(index)}
						<tr data-testid="assign-list-row-{index}">
							<td class="id">{line.externalID}</td>
							<td>
								{#if verdict?.submission && verdict.title !== null}
									<SubmissionLink
										submission={{ id: verdict.submission, title: verdict.title, venue: venue.id }}
										venueSlug={venue.slug}
									/>
								{/if}
							</td>
							<td class="who">
								<div class="stack">
									<!-- Change sits on the first line, beside the name as written, so it lines
									     up with the result badge in the next column rather than floating
									     beside the chosen person's details. -->
									<div class="written-row">
										<span class="written">{line.written}</span>
										{#if pins[index] !== undefined}
											<Button
												small
												testid="assign-list-row-{index}-change"
												strings={(l) => l.widget.volunteerPicker.change}
												action={() => {
													const next = { ...pins };
													delete next[index];
													setPins(next);
												}}
											/>
										{/if}
									</div>
									{#if match.status === 'resolved' && pins[index] === undefined}
										<ScholarLink id={match.id} size="small" newTab />
									{:else if (match.status !== 'none' && !looksLikeEmail(line.written)) || pins[index] !== undefined}
										<VolunteerPicker
											testid="assign-list-row-{index}-picker"
											name={line.written}
											role={role.name}
											{candidates}
											chosen={match.status === 'resolved' ? match.id : undefined}
											match={resolveWho(line.written, candidates)}
											choose={(id) => setPins({ ...pins, [index]: id })}
										/>
									{/if}
								</div>
							</td>
							<td>
								<div class="stack">
									<Status
										good={status.good}
										neutral={status.neutral}
										label={status.label}
										testid="assign-list-row-{index}-status"
									/>
									{#if verdict?.verdict === 'held' && verdict.holder}
										<span class="held">
											<Text path={(l) => l.page.assignList.heldBy} />
											<ScholarLink id={verdict.holder} size="small" newTab />
										</span>
									{/if}
									{#if cap}
										<Feedback
											warning
											testid="assign-list-row-{index}-over-cap"
											text={(l) =>
												l.page.assignList.overCap
													.replaceAll('{used}', cap.load.used.toString())
													.replaceAll('{adding}', cap.adding.toString())
													.replaceAll('{cap}', (cap.load.cap ?? 0).toString())}
										/>
									{/if}
								</div>
							</td>
						</tr>
					{/each}
				</Table>
			{/if}

			{#if current !== null && !current.final}
				<p data-testid="assign-list-summary">
					<Text
						path={(l) => l.page.assignList.summary}
						inputs={{
							ready: counts.ready.toString(),
							keep: counts.keep.toString(),
							problems: counts.problems.toString()
						}}
					/>
				</p>
				<Form>
					<Button
						strings={(l) => {
							const s =
								overCap.size > 0
									? l.page.assignList.button.assignOverCap
									: l.page.assignList.button.assign;
							const n = actionable.toString();
							return {
								tip: s.tip,
								label: s.label.replaceAll('{count}', n),
								warn: s.warn.replaceAll('{count}', n)
							};
						}}
						active={actionable > 0 && !unresolved}
						action={assign}
						testid="assign-list-assign"
					/>
				</Form>
			{:else if current !== null && current.final}
				<Feedback
					testid="assign-list-result"
					text={(l) =>
						l.page.assignList.result
							.replaceAll('{seated}', current.result.seated.toString())
							.replaceAll('{kept}', current.result.kept.toString())
							.replaceAll('{skipped}', current.result.skipped.toString())}
				/>
				<Form>
					<Button
						strings={(l) => l.page.assignList.button.another}
						action={reset}
						testid="assign-list-another"
					/>
				</Form>
			{/if}
		{/if}
	</Page>
{/if}

<style>
	.paste :global(textarea) {
		max-height: 16em;
		overflow-y: auto;
	}

	/* A manuscript ID is one token: broken at its hyphens it no longer reads as one. */
	.id {
		white-space: nowrap;
	}

	.who {
		min-width: 12em;
	}

	.stack {
		display: flex;
		flex-direction: column;
		gap: var(--spacing-half);
		align-items: flex-start;
	}

	.written-row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--spacing);
	}

	.written {
		color: var(--inactive-color);
		font-size: var(--small-font-size);
	}

	.held {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--spacing-half);
		font-size: var(--small-font-size);
	}
</style>
