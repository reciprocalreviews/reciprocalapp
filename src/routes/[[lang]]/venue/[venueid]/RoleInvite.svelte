<script lang="ts">
	import type { RoleRow, ScholarID, VenueRow } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import Loading from '$lib/components/Loading.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { getDB } from '$lib/data/CRUD';
	import {
		consume,
		type Invitee,
		inviteeName,
		lookupable,
		offers,
		parseQueries,
		spokenFor,
		unanswered,
		unmatched
	} from '$lib/data/inviteList';
	import { getLocaleContext } from '$routes/Contexts';
	import { handle } from '$routes/feedback.svelte';
	import { SvelteMap } from 'svelte/reactivity';

	let {
		venue,
		role,
		scholar,
		already
	}: {
		venue: VenueRow;
		role: RoleRow;
		/** The inviting admin. Non-optional: the caller already establishes that somebody
		 * is signed in before rendering this. */
		scholar: ScholarID;
		/** Scholars who already have a volunteer record for this role, in any state.
		 *
		 * Ids rather than the records, because the only question here is whether somebody
		 * can be added, and create_volunteer answers it from the (scholar, role) pair
		 * alone — it refuses a second row whether the first is invited, accepted,
		 * declined, or paused. Taking the records would invite this component to start
		 * re-deciding that, and the decision belongs to the database. */
		already: ScholarID[];
	} = $props();

	const db = getDB();
	const locale = getLocaleContext();

	/** How long to wait after a keystroke before asking who the queries match, so a
	 * pasted list isn't a query per character. Matches ScholarSearch and WebAddress. */
	const DEBOUNCE_MS = 250;

	let text = $state('');

	/** The scholars chosen from the matches, in the order they were chosen. This — not the
	 * field — is what the invitation sends. The field holds the questions still waiting on
	 * an answer; this holds the decision. */
	let staged = $state<Invitee[]>([]);

	/** What each query has matched so far, keyed by the query text. inviteList's `Answers`
	 * explains why by text and not by position.
	 *
	 * A cache across lookups rather than a snapshot of the last answer: typing a fourth
	 * query must not blank the three already answered, and re-asking about answered ones
	 * would be a query per keystroke.
	 *
	 * A SvelteMap, because a plain Map in `$state` is not proxied and the derivations
	 * below would never see a write. */
	let answers = new SvelteMap<string, Invitee[]>();

	/** Queries already asked about, whether or not the answer has landed; and queries seen
	 * but not yet asked about.
	 *
	 * Plain Sets, not SvelteSets, and deliberately so: the effect below both reads and
	 * writes these, and a reactive Set would re-trigger it on its own writes forever.
	 * Nothing renders from them either — they are bookkeeping about what has been asked,
	 * not about what the field says. `pending` accumulates across debounce resets; without
	 * it, typing a second query would clear the timer holding the first and the first
	 * would never be looked up at all — marked as asked, and left searching. */
	let requested = new Set<string>();
	let pending = new Set<string>();

	let timer: ReturnType<typeof setTimeout> | undefined = undefined;
	/** Set from this component's teardown, so a lookup that lands afterwards doesn't write
	 * into a component that's gone.
	 *
	 * No per-request sequence guard here, unlike ScholarSearch: that answers one question
	 * over and over, where a slow earlier answer really does overwrite a later one. Here
	 * every answer is written under the query it is about, so two of them landing out of
	 * order still put the right answer in the right place. */
	let gone = false;

	const queries = $derived(parseQueries(text));
	/** Everybody who cannot be added: already on this role's list, or already chosen. */
	const accounted = $derived(new Set<string>([...already, ...staged.map((s) => s.id)]));
	const matches = $derived(offers(queries, answers, accounted));
	const searching = $derived(unanswered(queries, answers).length > 0);
	const nobody = $derived(unmatched(queries, answers));
	const taken = $derived(spokenFor(queries, answers, accounted));

	$effect(() => {
		const fresh = unanswered(queries, answers).filter((query) => !requested.has(query));
		if (fresh.length === 0) return;
		for (const query of fresh) pending.add(query);

		clearTimeout(timer);
		timer = setTimeout(async () => {
			const asking = [...pending];
			pending.clear();
			for (const query of asking) requested.add(query);

			// Two passes, not one. Addresses and ORCID iDs go in a single batched lookup;
			// names go one query each, because scholarsByNameQuery's `limit(3)` is per
			// query — merged into one `or(...ilike...)` it would become a cap on the whole
			// round, and three matches for the first name would leave nothing for the rest.
			const addresses = asking.filter(lookupable);
			const names = asking.filter((query) => !lookupable(query));
			const [matched, searched] = await Promise.all([
				db().findScholarsByAddresses(addresses),
				Promise.all(names.map(async (n) => [n, await db().findScholarsByName(n)] as const))
			]);
			if (gone) return;

			// A failed lookup is not an answer. Caching an empty array would report everyone
			// as matching nobody, which is a claim about them rather than about the request;
			// forgetting we asked lets the next keystroke try again. Until then the query
			// reads as still searching, which is the safe direction to fail in.
			if (matched.error) for (const address of addresses) requested.delete(address);
			else
				for (const address of addresses) {
					const found = matched.data.get(address);
					answers.set(address, found ? [found] : []);
				}

			for (const [name, { data, error }] of searched) {
				if (error) requested.delete(name);
				else answers.set(name, data);
			}
		}, DEBOUNCE_MS);
	});

	$effect(() => () => {
		gone = true;
		clearTimeout(timer);
	});
</script>

<Form>
	<Paragraph text={(l) => l.view.roles.paragraph.inviteDescription} />

	<div class="stretch">
		<TextField
			strings={(l) => l.view.roles.field.invite}
			stretch
			bind:text
			testid="role-invite-field-{role.name}"
		/>
	</div>

	{#if matches.length > 0 || searching}
		<fieldset data-testid="role-invite-matches-{role.name}">
			<legend>{locale().view.roles.fieldset.matches}</legend>
			{#each matches as match (match.id)}
				{@const name = inviteeName(match)}
				<Button
					small
					strings={(l) => ({
						// The name goes in the TIP as well as the label, because the tip is the
						// button's aria-label: a row of buttons all announcing "Choose" is
						// unusable by voice or screen reader. Same reasoning as ScholarMatches.
						tip: l.widget.scholarSearch.choose.tip.replace('{name}', name),
						label: name
					})}
					testid="role-invite-match-{role.name}-{match.id}"
					action={() => {
						staged = [...staged, match];
						text = consume(text, match.id, answers);
					}}>{name}</Button
				>
			{/each}
			<!-- Last, so matches that have already landed don't jump when another answer
			     arrives. Answers arrive independently — one batched address lookup and one
			     query per name — so this means "more may still come", not "nothing yet". -->
			{#if searching}<Loading />{/if}
		</fieldset>
	{/if}

	{#if staged.length > 0}
		<fieldset data-testid="role-invite-invites-{role.name}">
			<legend>{locale().view.roles.fieldset.invites}</legend>
			{#each staged as invitee (invitee.id)}
				{@const name = inviteeName(invitee)}
				<span class="invitee" data-testid="role-invite-invitee-{role.name}-{invitee.id}"
					><ScholarLink id={{ id: invitee.id, name }} />&nbsp;<Button
						strings={(l) => ({
							tip: l.view.roles.button.removeInvite.tip.replace('{name}', name),
							label: l.view.roles.button.removeInvite.label
						})}
						testid="role-invite-remove-{role.name}-{invitee.id}"
						action={() => (staged = staged.filter((s) => s.id !== invitee.id))}
					/></span
				>
			{/each}
		</fieldset>
	{/if}

	{#if nobody.length > 0}
		<Feedback
			warning
			inline={false}
			text={(l) => l.view.roles.feedback.inviteUnmatched}
			inputs={{ queries: nobody.join(', ') }}
			testid="role-invite-unmatched-{role.name}"
		/>
	{/if}

	{#if taken.length > 0}
		<Feedback
			inline={false}
			text={(l) => l.view.roles.feedback.inviteAlready}
			inputs={{ queries: taken.join(', ') }}
			testid="role-invite-already-{role.name}"
		/>
	{/if}

	<Button
		strings={(l) => l.view.roles.button.invite}
		testid="role-invite-button-{role.name}"
		active={staged.length > 0}
		action={async () => {
			if (
				await handle(
					db().inviteToRole(
						scholar,
						role,
						venue,
						staged.map((s) => s.id)
					),
					locale().view.roles.feedback.invited
				)
			)
				// Only the chosen list is cleared. Choosing each of them already took their
				// query out of the field, so what is left there is unfinished work — a name
				// still being typed, or one that matched nobody — and discarding it because a
				// different invitation succeeded would be throwing away somebody else's
				// half-typed name. The answers cache is left alone too: handle() awaits
				// invalidateAll(), so `already` grows to include the people just invited and
				// they drop out of the matches on their own.
				staged = [];
		}}
	/>
</Form>

<style>
	/* Form is a column flex container with `align-items: flex-start`, so a block child
	   shrink-wraps to its content and a `flex-wrap` on it can never fire — the row grows
	   sideways instead of wrapping. Stretching is what gives these rows a width to wrap
	   inside. The venue proposal form solves the same problem the same way, with
	   `width: 100%` on its `.form-section`. */
	.stretch,
	fieldset {
		align-self: stretch;
	}

	fieldset {
		/* Overriding the global fieldset rule in app.html, which is a row that does not
		   wrap. Svelte's scoped selectors carry a class, so this wins on specificity and
		   needs no `!important`. */
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		align-items: baseline;
		border: none;
		padding: 0;
		/* Row gap, then column gap. A Button's box-shadow reaches about 3px past its border
		   box, so a half-spacing column gap reads as almost no gap at all between two of
		   them; a wrapped row's vertical rhythm has no such problem. */
		gap: var(--spacing-half) var(--spacing);
	}

	legend {
		/* app.html already italicizes this. The size is what makes it read as a caption for
		   the row rather than as one of the things in it. */
		font-size: var(--small-font-size);
	}

	.invitee {
		/* One flex item, so a scholar's link and their remove button cannot be wrapped onto
		   different lines from one another. */
		white-space: nowrap;
	}
</style>
