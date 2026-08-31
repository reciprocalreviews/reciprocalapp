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
		query = undefined,
		choose = undefined,
		testid = undefined
	}: {
		text: string;
		strings: (l: Locale) => TextFieldText | NotedTextFieldText;
		/** Extra rules on top of the search, e.g. "admins can't be minters". */
		valid?: undefined | ((text: string) => ((l: LocaleText) => string) | undefined);
		size?: number | undefined;
		name?: string | undefined;
		showResolved?: boolean;
		/** What part of the field to search for. Defaults to the whole thing; a
		 * field holding a comma-separated list searches only its last segment. */
		query?: ((text: string) => string) | undefined;
		/** What choosing a match means. Defaults to replacing the text with the
		 * chosen scholar's ORCID iD, which is what a single-scholar field wants;
		 * the role invite overrides it to append to a comma-separated list. */
		choose?: ((match: ScholarMatch) => void) | undefined;
		testid?: string;
	} = $props();

	const db = getDB();
	const search = new ScholarSearch(db);

	function chooseMatch(match: ScholarMatch) {
		if (choose) choose(match);
		else if (match.orcid !== null) text = match.orcid;
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
		change={(value) => search.change(query ? query(value) : value)}
		done={() => search.done(query ? query(text) : text)}
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
		   makes the field taller, which pushes whatever follows it — the Invite and
		   Add buttons that sit beside these fields — down the page. */
		align-items: flex-end;
		gap: var(--spacing-half);
	}

	.matches {
		display: inline-block;
	}
</style>
