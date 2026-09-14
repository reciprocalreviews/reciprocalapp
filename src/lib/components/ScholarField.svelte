<script lang="ts">
	import { getDB } from '$lib/data/CRUD';
	import type { ScholarMatch } from '$lib/data/SupabaseCRUD.svelte';
	import type Locale from '$lib/locales/Locale';
	import type { LocaleText, NotedTextFieldText, TextFieldText } from '$lib/locales/Locale';
	import ScholarMatches from './ScholarMatches.svelte';
	import { ScholarSearch } from './ScholarSearch.svelte';
	import TextField from './TextField.svelte';

	let {
		text = $bindable(''),
		strings,
		valid = undefined,
		size = undefined,
		name = undefined,
		showResolved = true,
		testid = undefined,
		search: provided = undefined
	}: {
		text: string;
		strings: (l: Locale) => TextFieldText | NotedTextFieldText;
		/** Extra rules on top of the search, e.g. "admins can't be minters". */
		valid?: undefined | ((text: string) => ((l: LocaleText) => string) | undefined);
		size?: number | undefined;
		name?: string | undefined;
		showResolved?: boolean;
		testid?: string;
		/** A search the caller owns, for when it needs the resolved scholar itself —
		 * to enable a button on it, or to check it against rows already on the page.
		 * Omitted, this component makes its own and keeps it private, which is all
		 * a field that only has to resolve its own text needs. */
		search?: ScholarSearch | undefined;
	} = $props();

	const db = getDB();
	// Not $derived: a ScholarSearch holds the debounce timer and the sequence counter
	// for a search in flight, so rebuilding it mid-search would strand both. A caller
	// hands one in for the life of the field or not at all.
	// svelte-ignore state_referenced_locally
	const search = provided ?? new ScholarSearch(db);

	function chooseMatch(match: ScholarMatch) {
		if (match.orcid !== null) text = match.orcid;
		search.choose(match);
	}
</script>

<span class="field">
	<TextField
		bind:text
		{strings}
		{size}
		{name}
		{valid}
		change={(value) => search.change(value)}
		done={() => search.done(text)}
		{testid}
	/>
	<!-- Wrapped, so this component owns the alignment. Feedback sets its own
	     `align-self: flex-start`, which would override any `align-items` set on the
	     row; against this plain span that declaration has no flex parent to act on,
	     and the wrapper is what gets aligned instead. -->
	<span class="matches">
		<ScholarMatches
			{search}
			choose={chooseMatch}
			{showResolved}
			foundTestid={testid ? `${testid}-found` : undefined}
			matchTestid={testid ? `${testid}-match` : undefined}
			noMatchesTestid={testid ? `${testid}-no-matches` : undefined}
		/>
	</span>
</span>

<style>
	.field {
		display: inline-flex;
		flex-direction: row;
		flex-wrap: wrap;
		/* `flex-end`, not `baseline`. A TextField is a label stacked above an input,
		   so its first baseline is the LABEL's — which left the matches and the "no
		   matches" feedback floating up beside the label instead of beside the field
		   they describe. Aligning the bottoms puts them level with the input.
		   Deliberately still a row: stacking them under the field reads well but
		   makes the field taller, which pushes whatever follows it — the Add buttons that
		   sit beside these fields — down the page. */
		align-items: flex-end;
		gap: var(--spacing-half);
	}

	.matches {
		display: inline-block;
	}
</style>
