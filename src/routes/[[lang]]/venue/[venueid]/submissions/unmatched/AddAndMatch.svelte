<script lang="ts">
	import type { RoleRow } from '#data/types.js';
	import Button from '#lib/components/Button.svelte';
	import Feedback from '#lib/components/Feedback.svelte';
	import Loading from '#lib/components/Loading.svelte';
	import ScholarLink from '#lib/components/ScholarLink.svelte';
	import { getDB, type UnmatchedNameScholar } from '#lib/data/CRUD.js';
	import { addFeedback } from '#routes/feedback.svelte.js';

	/** For whoever staffs the role (canStaffRole): the scholars named like an imported person who are not in the role
	 * yet, each with a button that adds them to it and matches them in one step. The button
	 * asks the viewer to confirm the person agreed, since it puts a commitment on their
	 * profile without them clicking anything.
	 *
	 * Looked up only when asked for. The page can hold hundreds of names, and most are
	 * matched from the role's volunteers without ever needing this. */
	let {
		venue,
		name,
		role,
		exclude,
		add,
		testid
	}: {
		venue: string;
		/** The name as the import spelled it. */
		name: string;
		role: RoleRow;
		/** Scholars the volunteer picker already offers, so nobody is listed twice. */
		exclude: Set<string>;
		add: (scholar: UnmatchedNameScholar) => Promise<void>;
		testid: string;
	} = $props();

	const db = getDB();

	let found = $state<UnmatchedNameScholar[] | undefined>(undefined);
	let searching = $state(false);

	const offered = $derived((found ?? []).filter((s) => !exclude.has(s.id)));

	async function find() {
		searching = true;
		const { data, error } = await db().getUnmatchedNameScholars(venue, name, role.id);
		searching = false;
		// A failed lookup is not an answer; leave the button so the admin can try again.
		if (error) addFeedback(error.message, 'error');
		else found = data;
	}
</script>

{#if found === undefined}
	{#if searching}<Loading />{:else}
		<Button small testid="{testid}-find" strings={(l) => l.page.unmatched.add.find} action={find} />
	{/if}
{:else if offered.length === 0}
	<Feedback
		testid="{testid}-nobody"
		text={(l) => l.page.unmatched.add.nobody.replaceAll('{name}', name)}
	/>
{:else}
	{#each offered as scholar (scholar.id)}
		{@const who = scholar.name ?? name}
		<div class="candidate" data-testid="{testid}-candidate-{scholar.id}">
			<span class="who"
				><ScholarLink id={{ id: scholar.id, name: scholar.name }} newTab />
				{#if scholar.email}<span class="detail">{scholar.email}</span>{/if}
				{#if scholar.orcid}<span class="detail">{scholar.orcid}</span>{/if}</span
			>
			<Button
				small
				testid="{testid}-add-{scholar.id}"
				strings={(l) => {
					const fill = (text: string) =>
						text.replaceAll('{name}', who).replaceAll('{role}', role.name);
					const text = l.page.unmatched.add.button;
					return { tip: fill(text.tip), label: fill(text.label), warn: fill(text.warn) };
				}}
				action={() => add(scholar)}
			/>
		</div>
	{/each}
{/if}

<style>
	.candidate {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: var(--spacing-half) var(--spacing);
	}

	.who {
		display: inline-flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: var(--spacing-half);
	}

	.detail {
		font-size: var(--small-font-size);
	}
</style>
