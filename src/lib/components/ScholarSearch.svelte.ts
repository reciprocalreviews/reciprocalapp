import type CRUD from '$lib/data/CRUD';
import type { ScholarMatch } from '$lib/data/SupabaseCRUD.svelte';
import { validEmail, validORCID } from '$lib/validation';

/** How far along the ORCID/email lookup is for one field. */
export type ScholarState =
	| { status: 'idle' }
	| { status: 'loading' }
	| { status: 'found'; id: string }
	| { status: 'notfound' };

/** A field's name search. `done` with no matches is a distinct state from
 * `none`: "we looked and found nobody" has to read differently from "you
 * haven't typed a name yet", which is otherwise the same empty space. */
export type NameSearch =
	{ status: 'none' } | { status: 'searching' } | { status: 'done'; matches: ScholarMatch[] };

/** How long to wait after a keystroke before searching, so a name isn't a query
 * per character. */
const DEBOUNCE_MS = 250;

/** The shortest name fragment worth searching for. */
const MIN_QUERY = 2;

/**
 * The behaviour behind a field that resolves text to a scholar: an ORCID iD or
 * email address looked up on blur, or a name searched for as it is typed, with
 * matches offered for the author to pick from.
 *
 * This is a class rather than a component because its two consumers need the
 * field and the results in different places in the DOM — the new-submission form
 * puts the input in one table cell and the matches in the next one over, which no
 * single wrapping component can express. `ScholarMatches.svelte` renders the
 * state, and `ScholarField.svelte` composes the two for the ordinary case where
 * they sit together.
 */
export class ScholarSearch {
	/** How the ORCID/email lookup stands. */
	state = $state<ScholarState>({ status: 'idle' });

	/** How the name search stands. */
	search = $state<NameSearch>({ status: 'none' });

	private readonly db: () => CRUD;
	private timer: ReturnType<typeof setTimeout> | undefined = undefined;
	/** Bumped per request, so a slow earlier search can't overwrite the results of
	 * a later one when it finally lands. */
	private sequence = 0;

	constructor(db: () => CRUD, resolved?: string) {
		this.db = db;
		// A field that starts pre-filled with a known scholar starts resolved, rather
		// than making someone blur it to see a name we already have.
		if (resolved !== undefined) this.state = { status: 'found', id: resolved };
	}

	/** Called on every keystroke. Searches by name when what's typed plainly isn't
	 * an ORCID iD, and resets the resolution, since the text no longer describes
	 * whichever scholar was last found. */
	change(text: string) {
		this.state = { status: 'idle' };
		this.searchByName(text);
	}

	/** Search scholars by name as the text is typed. */
	private searchByName(text: string) {
		clearTimeout(this.timer);
		const query = text.trim();
		// Too short, or already an ORCID: nothing to search for, and no result to
		// report either way.
		if (validORCID(query) || query.length < MIN_QUERY) {
			this.sequence++;
			this.search = { status: 'none' };
			return;
		}
		this.timer = setTimeout(async () => {
			const sequence = ++this.sequence;
			this.search = { status: 'searching' };
			const { data } = await this.db().findScholarsByName(query);
			// Ignore a response that's already been typed past.
			if (this.sequence !== sequence) return;
			this.search = { status: 'done', matches: data };
		}, DEBOUNCE_MS);
	}

	/** Called on blur or Enter: resolve an ORCID iD or email address to a scholar.
	 * Text that is neither is left alone rather than looked up — a half-typed name
	 * would otherwise come back "not found" and mark the field wrong for saying
	 * exactly what it was supposed to say. */
	async done(text: string) {
		const value = text.trim();
		if (!validORCID(value) && !validEmail(value)) return;
		if (this.state.status !== 'idle') return;
		this.state = { status: 'loading' };
		const { data } = await this.db().findScholar(value);
		this.state = data ? { status: 'found', id: data } : { status: 'notfound' };
	}

	/** Adopt a searched-for scholar. The field is already resolved, so no lookup
	 * round trip is needed. Retires any search still in flight along with its
	 * results. */
	choose(match: ScholarMatch) {
		clearTimeout(this.timer);
		this.sequence++;
		this.search = { status: 'none' };
		this.state = { status: 'found', id: match.id };
	}

	/** Forget any resolution and any search in flight. */
	reset() {
		clearTimeout(this.timer);
		this.sequence++;
		this.search = { status: 'none' };
		this.state = { status: 'idle' };
	}

	/** True when the text was looked up and matched nobody. */
	get notFound() {
		return this.state.status === 'notfound';
	}

	/** The resolved scholar's id, if there is one. */
	get id(): string | undefined {
		return this.state.status === 'found' ? this.state.id : undefined;
	}

	/** Stop the pending search, if any. Call from an effect's teardown so a
	 * removed field can't land results into a component that's gone. */
	dispose() {
		clearTimeout(this.timer);
		this.sequence++;
	}
}
