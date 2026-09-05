import type { Database } from '$data/database';
import { dedupeAddresses } from './addresses';
import type { AuthError, PostgrestError, QueryData, SupabaseClient } from '@supabase/supabase-js';
import type {
	AssignmentID,
	AssignmentRow,
	CompensationRow,
	ConflictRow,
	CurrencyID,
	CurrencyRow,
	PreferenceLevelID,
	PreferenceLevelRow,
	ProposalID,
	ProposalRow,
	Response,
	RoleID,
	RoleRow,
	ScholarID,
	ScholarRow,
	SubmissionID,
	SubmissionRow,
	SubmissionType,
	SubmissionTypeID,
	SupporterID,
	TokenID,
	TransactionID,
	TransactionRow,
	TransactionStatus,
	VenueID,
	VenueRow,
	VolunteerID,
	VolunteerRow,
	ThanksID,
	ThanksRow,
	NotificationSettingRow,
	ThanksStatus
} from '../../data/types';
import { renderEmail, type EmailType, type OptionalEmailType } from '../../email/templates';
import type Locale from '../locales/Locale';
import CRUD, {
	type BulkImportResult,
	type Charge,
	type ChargeCoverage,
	type EnsureScholarOutcome,
	type ImportedSubmission,
	type MarkSubmissionDoneOutcome,
	type Notification,
	type ReadResult,
	type Result,
	type SubmissionBlocker
} from './CRUD';
import Scholar from './Scholar.svelte';
import { isUUID } from '../validation';
import { venuePath } from './venuePath';

// A constant page size for paginated queries.
export const PAGE_SIZE = 10;

/** Shape of the JSONB returned by the complete_assignment Postgres RPC.
 * The two branches correspond to the two outcomes of an attempt to pay a
 * completed assignment: either the venue had enough tokens and they moved
 * to the scholar, or it didn't and a proposed mint transaction was queued
 * for a minter to approve. */
type CompleteAssignmentResult =
	| {
			status: 'transferred';
			transaction_id: TransactionID;
			amount: number;
			role_name: string;
			venue_id: VenueID;
			scholar_id: ScholarID;
			submission_id: SubmissionID;
	  }
	| {
			status: 'insufficient';
			shortfall: number;
			amount: number;
			mint_transaction_id: TransactionID;
			venue_id: VenueID;
			venue_title: string;
			currency_id: CurrencyID;
			scholar_id: ScholarID;
			submission_id: SubmissionID;
			role_name: string;
	  };

/** Runtime narrowing of the Json that Supabase returns from the
 * complete_assignment RPC. Uses TypeScript's `in` narrowing so no
 * `as` cast is needed. */
export function isCompleteAssignmentResult(value: unknown): value is CompleteAssignmentResult {
	if (typeof value !== 'object' || value === null || !('status' in value)) return false;
	return value.status === 'transferred' || value.status === 'insufficient';
}

/** Shape of the JSONB returned by the mark_submission_done Postgres RPC. */
type MarkSubmissionDonePayout = {
	transaction_id: TransactionID;
	scholar_id: ScholarID;
	role_name: string;
	amount: number;
};

type MarkSubmissionDoneResult =
	| {
			status: 'completed';
			submission_id: SubmissionID;
			venue_id: VenueID;
			currency_id: CurrencyID;
			total_amount: number;
			payouts: MarkSubmissionDonePayout[];
	  }
	| {
			status: 'blocked';
			blockers: SubmissionBlocker[];
	  }
	| {
			status: 'insufficient';
			shortfall: number;
			total_amount: number;
			mint_transaction_id: TransactionID;
			venue_id: VenueID;
			venue_title: string;
			currency_id: CurrencyID;
			submission_id: SubmissionID;
	  };

export function isMarkSubmissionDoneResult(value: unknown): value is MarkSubmissionDoneResult {
	if (typeof value !== 'object' || value === null || !('status' in value)) return false;
	return (
		value.status === 'completed' || value.status === 'blocked' || value.status === 'insufficient'
	);
}

/** Read a string field from a jsonb object returned by an RPC, or null if
 * absent or the wrong type. The atomic-CRUD RPCs return jsonb_build_object
 * payloads (see migration 20260608000000_atomic_crud.sql). */
export function stringField(value: unknown, key: string): string | null {
	if (typeof value !== 'object' || value === null || !(key in value)) return null;
	const field = (value as Record<string, unknown>)[key];
	return typeof field === 'string' ? field : null;
}

/** Read a number field from a jsonb object returned by an RPC, or null if
 * absent or the wrong type. */
export function numberField(value: unknown, key: string): number | null {
	if (typeof value !== 'object' || value === null || !(key in value)) return null;
	const field = (value as Record<string, unknown>)[key];
	return typeof field === 'number' ? field : null;
}

/** Read a boolean field from a jsonb object returned by an RPC, or null if
 * absent or the wrong type. */
export function booleanField(value: unknown, key: string): boolean | null {
	if (typeof value !== 'object' || value === null || !(key in value)) return null;
	const field = (value as Record<string, unknown>)[key];
	return typeof field === 'boolean' ? field : null;
}

/** Read a string[] field from a jsonb object returned by an RPC, or null if
 * absent or not an array of strings. */
export function stringArrayField(value: unknown, key: string): string[] | null {
	if (typeof value !== 'object' || value === null || !(key in value)) return null;
	const field = (value as Record<string, unknown>)[key];
	if (!Array.isArray(field) || field.some((v) => typeof v !== 'string')) return null;
	return field as string[];
}

/** Map an atomic-CRUD RPC's custom SQLSTATE (the `RRxxx` codes set via
 * `raise ... using errcode` in migration 20260608000000_atomic_crud.sql) to a
 * specific localized error key, falling back to a generic one. This keeps the
 * user-facing headline specific and localized for the user-actionable failures
 * (insufficient tokens, self-dealing, already approved, already volunteered)
 * instead of collapsing every failure to one generic message per RPC. */
export function rpcErrorKey(
	error: PostgrestError | null,
	fallback: keyof Locale['error'],
	map: Record<string, keyof Locale['error']>
): keyof Locale['error'] {
	const code = error?.code;
	return (code !== undefined && map[code]) || fallback;
}

// --- Typed query factories for embedded/joined reads ---
// Reads with embedded resources (PostgREST `select('*, related(...)')`) or
// column aggregates produce row shapes that aren't a plain generated Row type.
// Each factory below captures the exact query so its inferred element type can
// be exported and reused both here and by the abstract CRUD interface, keeping
// the read path fully typed without hand-maintaining the composite shapes.

function venueVolunteersQuery(client: SupabaseClient<Database>, venue: VenueID) {
	return client.from('volunteers').select('*, roles!inner(venueid)').eq('roles.venueid', venue);
}
export type VenueVolunteer = QueryData<ReturnType<typeof venueVolunteersQuery>>[number];

function venueSettingsVolunteersQuery(client: SupabaseClient<Database>, venue: VenueID) {
	return client.from('volunteers').select('*, roles (venueid)').eq('roles.venueid', venue);
}
export type VenueSettingsVolunteer = QueryData<
	ReturnType<typeof venueSettingsVolunteersQuery>
>[number];

function venueCommitmentsQuery(client: SupabaseClient<Database>, venue: VenueID) {
	return client
		.from('volunteers')
		.select('*, scholars (name, email, orcid), roles!inner(name, venueid)')
		.eq('roles.venueid', venue);
}
export type VenueCommitment = QueryData<ReturnType<typeof venueCommitmentsQuery>>[number];

function scholarVolunteeringQuery(client: SupabaseClient<Database>, scholar: ScholarID) {
	return client
		.from('volunteers')
		.select('*, roles(name, venueid, approver)')
		.eq('scholarid', scholar)
		.or('active.eq.true,accepted.eq.invited');
}
export type ScholarVolunteering = QueryData<ReturnType<typeof scholarVolunteeringQuery>>[number];

function proposalSupportersQuery(client: SupabaseClient<Database>, proposal: ProposalID) {
	return client
		.from('supporters')
		.select('id, scholarid(id, name, email), message, created_at')
		.eq('proposalid', proposal);
}
export type ProposalSupporter = QueryData<ReturnType<typeof proposalSupportersQuery>>[number];

function scholarReviewsQuery(client: SupabaseClient<Database>, scholar: ScholarID) {
	return client
		.from('assignments')
		.select('*, submissions(*)')
		.eq('scholar', scholar)
		.eq('completed', false)
		.eq('approved', true);
}
export type ScholarReview = QueryData<ReturnType<typeof scholarReviewsQuery>>[number];

function assignmentsForApprovalQuery(client: SupabaseClient<Database>, roleIDs: RoleID[]) {
	return client
		.from('assignments')
		.select('*, scholars(*), submissions(*)')
		.in('role', roleIDs)
		.eq('approved', false);
}
export type AssignmentForApproval = QueryData<
	ReturnType<typeof assignmentsForApprovalQuery>
>[number];

/** Assignments on the given roles whose scholar has requested compensation but
 * hasn't been paid — the approver's "work awaiting your approval" task list. */
function assignmentsAwaitingCompensationQuery(client: SupabaseClient<Database>, roleIDs: RoleID[]) {
	return client
		.from('assignments')
		.select('*, scholars(*), submissions(*)')
		.in('role', roleIDs)
		.eq('approved', true)
		.eq('completed', false)
		.not('compensation_requested_at', 'is', null);
}
export type AssignmentAwaitingCompensation = QueryData<
	ReturnType<typeof assignmentsAwaitingCompensationQuery>
>[number];

/** How many tokens of one currency each named scholar holds. Scholars holding
 * none are absent rather than zero; callers default.
 *
 * An RPC rather than a PostgREST aggregate over `tokens`: the scholar list is a
 * venue's whole volunteer roster, and as an `in.(...)` query string five thousand
 * UUIDs is a ~185KB URL and a 414 before Postgres ever sees it. As an argument it
 * travels in the POST body. The grouped result was also subject to `max_rows`,
 * so past a thousand distinct holders the balances were silently truncated. */
/** Every `transactions` column except `tokens`, which is one UUID per token
 * moved. The lists render only its length, and `amount` is that length as a
 * generated column — so selecting `*` meant detoasting and shipping tens of
 * thousands of UUIDs per page to draw a number the row already carries. */
const TRANSACTION_LIST_COLUMNS =
	'id, created_at, creator, from_scholar, from_venue, to_scholar, to_venue, currency, purpose, status, decliner, decline_reason, seq, amount';

/** The three paginated transaction lists, which differ only in their filter.
 *
 * `withCount` is true only for the first page. The total is displayed and drives
 * the "load more" stop condition, so it has to be exact — but it was being asked
 * for on EVERY page, and an exact count re-runs the whole filtered scan through
 * the transactions SELECT policy, whose venue and minter branches are correlated
 * subqueries evaluated per row. Every "load more" was therefore paying for the
 * page twice: once for ten rows, once to recount every row the scholar can see. */
function transactionListQuery(client: SupabaseClient<Database>, withCount: boolean) {
	return client
		.from('transactions')
		.select(TRANSACTION_LIST_COLUMNS, withCount ? { count: 'exact' } : undefined);
}
export type TransactionListRow = QueryData<ReturnType<typeof transactionListQuery>>[number];

export type TokenBalance = Database['public']['Functions']['scholar_balances']['Returns'][number];

/** Total supply of a currency and how many scholars and venues hold any of it.
 * `currency_holder_counts` returns Json, so the shape is named here. */
export type CurrencyHolderCounts = {
	supply: number;
	scholars: number;
	venues: number;
};

/** Candidate co-authors matched by name. The columns are listed explicitly
 * because the scholars SELECT policy is public — a wildcard here would hand
 * out contact emails to anyone who can type into the author field. */
function scholarsByNameQuery(client: SupabaseClient<Database>, pattern: string) {
	return (
		client
			.from('scholars')
			.select('id, name, orcid')
			.ilike('name', pattern)
			.not('name', 'is', null)
			.not('orcid', 'is', null)
			// Ordered, because `limit` makes the order decide WHICH matches are offered,
			// not just their sequence. Without it the three shown are whichever three
			// Postgres happens to reach first in heap order — which shifts every time any
			// scholar's row is updated, so searching the same name twice can offer
			// different people.
			.order('name')
			.limit(3)
	);
}
export type ScholarMatch = QueryData<ReturnType<typeof scholarsByNameQuery>>[number];

/** A seeded scholar offered on the local-only sign-in list. */
export type DevScholar = Pick<ScholarRow, 'id' | 'name' | 'email' | 'steward'>;

export default class SupabaseCRUD extends CRUD {
	/** Reference to the database connection. */
	readonly client: SupabaseClient<Database>;

	/** A set of reactive scholar record states, indexed by ID */
	private readonly scholars: Map<ScholarID, Scholar> = new Map();

	/** The locale for error messages */
	private readonly locale: Locale;

	constructor(client: SupabaseClient, locale: Locale) {
		super();
		this.client = client;
		this.locale = locale;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Internals — shared error/read/write helpers
	// ─────────────────────────────────────────────────────────────────────────

	/** A helper function for creating a result with an error ID. */
	error(id: keyof Locale['error'], error?: AuthError | PostgrestError | null, details?: string) {
		const message = this.locale.error[id] + (details ? `: ${details}` : '');
		console.error(message, error);
		return { error: { message, details: error ?? undefined } };
	}

	/** A helper function for returning data or an error, depending on what was returned. */
	errorOrEmpty(id: keyof Locale['error'], error: PostgrestError | null) {
		return error ? this.error(id, error) : {};
	}

	// These three all return the failure alongside the data rather than only logging
	// it. A caller that doesn't care can keep destructuring `data` exactly as before,
	// but one that does can now tell a MISSING row from a FAILED read — which
	// `.maybeSingle()` distinguishes (null data with a null error means the row isn't
	// there) and this layer used to throw away. The scholar route depends on it to
	// answer a 404 instead of rendering "unable to load" for every case alike.

	/** Run a multi-row read, log on failure, and resolve with the rows (null on
	 * error), preserving the query's inferred element type. Used by the page-load
	 * read methods (#137). */
	private async rows<Row>(
		id: keyof Locale['error'],
		query: PromiseLike<{ data: Row[] | null; error: PostgrestError | null }>
	): Promise<ReadResult<Row[] | null>> {
		const { data, error } = await query;
		return { data, ...(error ? this.error(id, error) : {}) };
	}

	/** Run a single-row read (`.maybeSingle()`), log on failure, and resolve with
	 * the row or null. */
	private async row<Row>(
		id: keyof Locale['error'],
		query: PromiseLike<{ data: Row | null; error: PostgrestError | null }>
	): Promise<ReadResult<Row | null>> {
		const { data, error } = await query;
		return { data: data ?? null, ...(error ? this.error(id, error) : {}) };
	}

	/** Run a count query (`{ count: 'exact', head: true }`), log on failure, and
	 * resolve with the count or null. */
	private async count(
		id: keyof Locale['error'],
		query: PromiseLike<{ count: number | null; error: PostgrestError | null }>
	): Promise<ReadResult<number | null>> {
		const { count, error } = await query;
		return { data: count, ...(error ? this.error(id, error) : {}) };
	}

	// Per-table single-row column updaters keyed by `id`. These collapse the many
	// trivial `update({...}).eq('id', id)` + errorOrEmpty writes into one place.
	// (A single generic updater can't be written because Supabase's typed client
	// rejects a `.from(table)` call with a non-literal table name.)

	private async updateVenue(
		id: VenueID,
		patch: Database['public']['Tables']['venues']['Update'],
		errorKey: keyof Locale['error']
	): Promise<Result> {
		const { error } = await this.client.from('venues').update(patch).eq('id', id);
		return this.errorOrEmpty(errorKey, error);
	}

	private async updateRole(
		id: RoleID,
		patch: Database['public']['Tables']['roles']['Update'],
		errorKey: keyof Locale['error']
	): Promise<Result> {
		const { error } = await this.client.from('roles').update(patch).eq('id', id);
		return this.errorOrEmpty(errorKey, error);
	}

	private async updateProposal(
		id: ProposalID,
		patch: Database['public']['Tables']['proposals']['Update'],
		errorKey: keyof Locale['error']
	): Promise<Result> {
		const { error } = await this.client.from('proposals').update(patch).eq('id', id);
		return this.errorOrEmpty(errorKey, error);
	}

	private async updateCurrency(
		id: CurrencyID,
		patch: Database['public']['Tables']['currencies']['Update'],
		errorKey: keyof Locale['error']
	): Promise<Result> {
		const { error } = await this.client.from('currencies').update(patch).eq('id', id);
		return this.errorOrEmpty(errorKey, error);
	}

	private async updateVolunteer(
		id: VolunteerID,
		patch: Database['public']['Tables']['volunteers']['Update'],
		errorKey: keyof Locale['error']
	): Promise<Result> {
		const { error } = await this.client.from('volunteers').update(patch).eq('id', id);
		return this.errorOrEmpty(errorKey, error);
	}

	private async updateSubmission(
		id: SubmissionID,
		patch: Database['public']['Tables']['submissions']['Update'],
		errorKey: keyof Locale['error']
	): Promise<Result> {
		const { error } = await this.client.from('submissions').update(patch).eq('id', id);
		return this.errorOrEmpty(errorKey, error);
	}

	private async updatePreferenceLevel(
		id: PreferenceLevelID,
		patch: Database['public']['Tables']['preference_levels']['Update'],
		errorKey: keyof Locale['error']
	): Promise<Result> {
		const { error } = await this.client.from('preference_levels').update(patch).eq('id', id);
		return this.errorOrEmpty(errorKey, error);
	}

	/** Resolve a from/to entity reference to an id, looking up scholars by
	 * email/ORCID when needed. Used by transferTokens. */
	async resolveEntityID(
		kind: 'venueid' | 'scholarid' | 'emailorcid',
		id: VenueID | ScholarID | string
	): Promise<VenueID | ScholarID | null> {
		if (kind === 'venueid' || kind === 'scholarid') return id;
		const { data: scholar } = await this.findScholar(id);
		if (scholar === undefined) return null;
		return scholar;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Scholars
	// ─────────────────────────────────────────────────────────────────────────

	/** Register a reactive scholar state. */
	registerScholar(row: ScholarRow) {
		let scholar = this.scholars.get(row.id);
		if (scholar === undefined) {
			scholar = new Scholar(row);
			this.scholars.set(row.id, scholar);
		}
		return scholar;
	}

	async getScholarsForDevSignIn(): Promise<ReadResult<DevScholar[] | null>> {
		// Backs the local-only sign-in list on /login, so testing a flow as a
		// particular seeded scholar doesn't mean opening seed.sql to look up an
		// address. Reads nothing the scholars policy doesn't already make public,
		// and the page only renders the list against a local Supabase — but the
		// name says what it is for, so it isn't reached for casually.
		return this.rows(
			'LoadScholar',
			this.client.from('scholars').select('id, name, email, steward').order('name')
		);
	}

	async findScholarsByName(query: string): Promise<ReadResult<ScholarMatch[]>> {
		// Name search for the new-submission form, where an author may know a
		// co-author's name but not their ORCID. Scholars with no name are skipped
		// — that covers erased accounts, whose name is nulled — and so are those
		// with no ORCID, since an ORCID is what the form needs back. The wildcards
		// in the caller's text are escaped so a stray % doesn't match everyone.
		const escaped = query.trim().replaceAll('%', '\\%').replaceAll('_', '\\_');
		if (escaped.length === 0) return { data: [] };
		const { data, error } = await scholarsByNameQuery(this.client, `%${escaped}%`);
		if (error) {
			console.error(error);
			return { data: [], error: { message: this.locale.error.ScholarNotFound, details: error } };
		}
		return { data: data ?? [] };
	}

	async findScholar(emailOrORCID: string): Promise<Result<string>> {
		const { data: scholar, error } = await this.client
			.from('scholars')
			.select('id')
			.or(`orcid.eq.${emailOrORCID},email.eq.${emailOrORCID}`)
			.single();

		return error || scholar === null ? this.error('ScholarNotFound', error) : { data: scholar.id };
	}

	async findUnknownAddresses(addresses: string[]): Promise<ReadResult<string[]>> {
		// One query rather than one per address, and deliberately matched on `email` only.
		// `approve_venue_proposal` resolves proposal addresses against `scholars.email`, which
		// is written solely by the verification flow — so someone can hold an account and
		// still not be found here, having never verified this address. Matching on anything
		// wider (ORCID, say) would report addresses as known that approval would then reject.
		if (addresses.length === 0) return { data: [] };
		const { data, error } = await this.client
			.from('scholars')
			.select('email')
			.in('email', addresses);
		if (error) {
			console.error(error);
			return { data: [], error: { message: this.locale.error.ScholarNotFound, details: error } };
		}
		const known = new Set((data ?? []).map((scholar) => scholar.email));
		return { data: addresses.filter((address) => !known.has(address)) };
	}

	async getScholar(scholarID: ScholarID): Promise<Scholar | null> {
		const scholar = this.scholars.get(scholarID);
		if (scholar) return scholar;

		const { data, error } = await this.client
			.from('scholars')
			.select()
			.eq('id', scholarID)
			.single();
		if (error) return null;
		return this.registerScholar(data);
	}

	async convertORCIDsToScholars(
		orcids: string[]
	): Promise<Result<{ orcid: string | null; id: string }[]>> {
		// First, find the scholars with the specified ORCIDs.
		const { data: scholars, error: scholarError } = await this.client
			.from('scholars')
			.select('orcid, id')
			.in('orcid', orcids);
		if (scholarError || scholars === null || scholars.length !== orcids.length) {
			return this.error(
				'ScholarNotFound',
				scholarError ?? undefined,

				orcids.filter((o) => !scholars?.some((s) => s.orcid === o)).join(', ')
			);
		}
		return { data: scholars };
	}

	async updateScholarName(id: ScholarID, name: string): Promise<Result> {
		const { error } = await this.client.from('scholars').update({ name }).eq('id', id);
		if (error) return this.error('UpdateScholarName', error);
		else {
			const state = this.scholars.get(id);
			if (state) state.setName(name);
			return {};
		}
	}

	async updateScholarAvailability(id: ScholarID, available: boolean): Promise<Result> {
		const { error } = await this.client.from('scholars').update({ available }).eq('id', id);
		if (error) return this.error('UpdateScholarAvailability', error);
		else {
			const state = this.scholars.get(id);
			if (state) state.setAvailable(available);
			return {};
		}
	}

	/** Which optional notices this scholar has silenced. The RLS policy admits only the
	 * scholar's own rows, so this comes back empty for anyone else's profile — which is
	 * fine, because the controls are only rendered for the scholar themselves. */
	async getNotificationSettings(
		scholar: ScholarID
	): Promise<ReadResult<NotificationSettingRow[] | null>> {
		return this.rows(
			'LoadNotificationSettings',
			this.client.from('notification_settings').select().eq('scholar', scholar)
		);
	}

	/** Turn one optional notice on or off.
	 *
	 * An upsert rather than an insert-or-delete: a row saying `true` is equivalent to no
	 * row at all, so writing the preference either way is one round trip and the client
	 * never has to decide whether "back to the default" means deleting. The composite
	 * primary key is what makes the conflict target unambiguous. */
	async updateNotificationSetting(
		scholar: ScholarID,
		event: OptionalEmailType,
		enabled: boolean
	): Promise<Result> {
		const { error } = await this.client
			.from('notification_settings')
			.upsert({ scholar, event, enabled }, { onConflict: 'scholar,event' });
		if (error) return this.error('UpdateNotificationSetting', error);
		return {};
	}

	async updateScholarStatus(id: ScholarID, status: string): Promise<Result> {
		const { error } = await this.client
			.from('scholars')
			.update({ status, status_time: new Date().toISOString() })
			.eq('id', id);
		if (error) return this.error('UpdateScholarStatus', error);
		else {
			const state = this.scholars.get(id);
			if (state) state.setStatus(status);
			return {};
		}
	}

	/** Begin (or resend, or change to) contact-email verification for the current
	 * scholar (#27). We never write scholars.email directly — that column holds only a
	 * verified address, and the column privilege to write it was revoked besides.
	 *
	 * Everything happens inside the RPC: it records the pending candidate and a token
	 * hash, builds the link from the server's own configured origin, and queues the
	 * branded email. Nothing comes back. That is deliberate — an earlier version returned
	 * the raw token to this client, which let anyone read it out of the network tab and
	 * verify an address they did not control. For the same reason the caller supplies
	 * neither the message body nor the origin. */
	async requestEmailVerification(email: string): Promise<Result> {
		const { error } = await this.client.rpc('request_email_verification', { _email: email });
		if (error) return this.error('UpdateScholarEmail', error);
		return {};
	}

	async getScholarRow(id: ScholarID): Promise<ReadResult<ScholarRow | null>> {
		return this.row(
			'LoadScholar',
			this.client.from('scholars').select().eq('id', id).maybeSingle()
		);
	}

	async ensureScholar(): Promise<Result<EnsureScholarOutcome>> {
		const { data, error } = await this.client.rpc('ensure_scholar');
		if (error) return this.error('EnsureScholar', error);
		return { data: data as EnsureScholarOutcome };
	}

	async getScholarsByIDs(ids: ScholarID[]): Promise<ReadResult<ScholarRow[] | null>> {
		return this.rows('LoadScholar', this.client.from('scholars').select().in('id', ids));
	}

	async getScholarNames(
		ids: ScholarID[]
	): Promise<ReadResult<Pick<ScholarRow, 'id' | 'name'>[] | null>> {
		return this.rows('LoadScholar', this.client.from('scholars').select('id, name').in('id', ids));
	}

	async getStewards(): Promise<ReadResult<Pick<ScholarRow, 'id' | 'name'>[] | null>> {
		// Ordered, because this list is public (/about) and heap order is not stable:
		// Postgres moves a row's physical position on every UPDATE, so an unordered
		// list reshuffles whenever any steward edits their name or status.
		return this.rows(
			'LoadScholar',
			this.client.from('scholars').select('id, name').eq('steward', true).order('name')
		);
	}

	async getScholarAdminVenues(
		scholar: ScholarID
	): Promise<ReadResult<Pick<VenueRow, 'id' | 'title' | 'slug'>[] | null>> {
		return this.rows(
			'LoadVenue',
			this.client.from('venues').select('id, title, slug').contains('admins', [scholar])
		);
	}

	async getScholarMintingCurrencies(scholar: ScholarID): Promise<ReadResult<CurrencyRow[] | null>> {
		return this.rows(
			'LoadCurrency',
			this.client.from('currencies').select('*').contains('minters', [scholar])
		);
	}

	async getScholarVolunteering(
		scholar: ScholarID
	): Promise<ReadResult<ScholarVolunteering[] | null>> {
		return this.rows('LoadVolunteer', scholarVolunteeringQuery(this.client, scholar));
	}

	async getScholarActiveVolunteering(
		scholar: ScholarID,
		roleIDs: RoleID[]
	): Promise<ReadResult<VolunteerRow[] | null>> {
		return this.rows(
			'LoadVolunteer',
			this.client
				.from('volunteers')
				.select('*')
				.eq('scholarid', scholar)
				.eq('active', true)
				.eq('accepted', 'accepted')
				.in('roleid', roleIDs)
		);
	}

	async getScholarAcceptedVolunteering(
		scholar: ScholarID,
		roleIDs: RoleID[]
	): Promise<ReadResult<VolunteerRow[] | null>> {
		return this.rows(
			'LoadVolunteer',
			this.client
				.from('volunteers')
				.select('*')
				.eq('scholarid', scholar)
				.eq('accepted', 'accepted')
				.in('roleid', roleIDs)
		);
	}

	async getScholarSubmissions(scholar: ScholarID): Promise<ReadResult<SubmissionRow[] | null>> {
		return this.rows(
			'LoadSubmission',
			this.client.from('submissions').select('*').contains('authors', [scholar])
		);
	}

	async getScholarReviews(scholar: ScholarID): Promise<ReadResult<ScholarReview[] | null>> {
		return this.rows('LoadAssignment', scholarReviewsQuery(this.client, scholar));
	}

	/** How many tokens the scholar holds, per currency. The scholar page used to
	 * fetch one ROW PER TOKEN and re-filter that array once per currency; PostgREST
	 * caps a response at `max_rows`, so both the total and every per-currency figure
	 * silently stopped at 1000. This groups in the database instead. */
	async getScholarBalances(scholar: ScholarID): Promise<ReadResult<Record<string, number>>> {
		const { data, error } = await this.client
			.from('tokens')
			.select('currency, id.count()')
			.eq('scholar', scholar);
		if (error) {
			this.error('LoadToken', error);
			return { data: {} };
		}
		return {
			data: Object.fromEntries(data.map((row) => [row.currency, row.count]))
		};
	}

	async getScholarTokenCount(scholar: ScholarID): Promise<ReadResult<number>> {
		// A count rather than the rows: this runs in the root layout load, so on
		// every navigation, and a scholar can hold hundreds of individual token
		// rows. `head: true` asks Postgres for the count without the payload.
		const { count, error } = await this.client
			.from('tokens')
			.select('id', { count: 'exact', head: true })
			.eq('scholar', scholar);
		if (error) {
			console.error(error);
			return { data: 0, error: { message: this.locale.error.LoadToken, details: error } };
		}
		return { data: count ?? 0 };
	}

	async getScholarConflicts(scholar: ScholarID): Promise<ReadResult<ConflictRow[] | null>> {
		return this.rows(
			'LoadConflict',
			this.client.from('conflicts').select('*').eq('scholarid', scholar)
		);
	}

	async getScholarPriorSubmissions(
		venue: VenueID,
		scholar: ScholarID
	): Promise<
		ReadResult<Pick<SubmissionRow, 'id' | 'externalid' | 'title' | 'submission_type'>[] | null>
	> {
		return this.rows(
			'LoadSubmission',
			this.client
				.from('submissions')
				.select('id, externalid, title, submission_type')
				.eq('venue', venue)
				.contains('authors', [scholar])
		);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Venues
	// ─────────────────────────────────────────────────────────────────────────

	async editVenueDescription(id: VenueID, description: string) {
		return this.updateVenue(id, { description }, 'EditVenueDescription');
	}

	async editVenueAdmins(id: VenueID, admins: string[]) {
		return this.updateVenue(id, { admins: Array.from(new Set(admins)) }, 'EditVenueAdmins');
	}

	async addVenueAdmin(id: VenueID, emailOrORCID: string): Promise<Result> {
		const { data: venue, error: venueError } = await this.client
			.from('venues')
			.select()
			.eq('id', id)
			.single();

		if (venue === null) return this.error('EditVenueAddEditorVenueNotFound', venueError);

		const { data: scholarID, error: scholarError } = await this.findScholar(emailOrORCID);
		if (scholarID === undefined) return this.error('ScholarNotFound', scholarError?.details);

		if (venue.admins.includes(scholarID))
			return { error: { message: this.locale.error.EditVenueAddEditorAlreadyEditor } };

		return this.editVenueAdmins(id, Array.from(new Set([...venue.admins, scholarID])));
	}

	async editVenueTitle(id: VenueID, title: string) {
		return this.updateVenue(id, { title }, 'EditVenueTitle');
	}

	async editVenueURL(id: VenueID, url: string) {
		return this.updateVenue(id, { url }, 'EditVenueURL');
	}

	/**
	 * Set or change the venue's web address.
	 *
	 * The unique index, not the availability check the field runs while someone types, is
	 * what decides who gets a contested address: two venues can both be told an address is
	 * free in the same second, and only one write can win. So the collision is read off the
	 * error rather than prevented, and the loser is told the address was taken rather than
	 * shown a generic failure. `23514` is the format constraint, which the field's own
	 * validation should have caught — it means something reached here unvalidated.
	 */
	async editVenueSlug(id: VenueID, slug: string) {
		const { error } = await this.client
			.from('venues')
			.update({ slug: slug.trim().toLowerCase() })
			.eq('id', id);
		return this.errorOrEmpty(
			rpcErrorKey(error, 'EditVenueSlug', {
				'23505': 'VenueAddressTaken',
				'23514': 'VenueAddressInvalid'
			}),
			error
		);
	}

	async editVenueInactive(id: VenueID, inactive: string | null) {
		return this.updateVenue(id, { inactive }, 'EditVenueInactive');
	}

	async editVenueAnonymousAssignments(id: VenueID, anonymous_assignments: boolean) {
		return this.updateVenue(id, { anonymous_assignments }, 'EditVenueAnonymousAssignments');
	}

	async editVenueVetThanks(id: VenueID, vet_thanks: boolean) {
		return this.updateVenue(id, { vet_thanks }, 'EditVenueVetThanks');
	}

	async editVenueWelcomeAmount(id: VenueID, amount: number) {
		return this.updateVenue(id, { welcome_amount: amount }, 'EditVenueWelcomeAmount');
	}

	async editVenuePaymentFree(id: VenueID, paymentFree: boolean) {
		return this.updateVenue(id, { payment_free: paymentFree }, 'EditVenuePaymentFree');
	}

	async editVenueDoneVisibilityDays(id: VenueID, days: number) {
		return this.updateVenue(id, { done_visibility_days: days }, 'EditVenueDoneVisibilityDays');
	}

	async editVenueTransactionReminderFrequency(id: VenueID, days: number) {
		return this.updateVenue(
			id,
			{ transaction_reminder_frequency_days: days },
			'EditVenueTransactionReminderFrequency'
		);
	}

	async getVenue(id: VenueID): Promise<ReadResult<VenueRow | null>> {
		return this.row('LoadVenue', this.client.from('venues').select().eq('id', id).maybeSingle());
	}

	/**
	 * Resolve a venue from a URL path segment.
	 *
	 * The segment is the venue's web address once it has chosen one, and its id until then.
	 * Which column to query is decided by looking at the segment rather than by trying one
	 * and falling back to the other: `venues_slug_check` forbids an address shaped like a
	 * UUID precisely so this stays a decision and not a guess, and a UUID compared against a
	 * text column (or the reverse) is a wasted round trip at best.
	 */
	async getVenueByPath(path: string): Promise<ReadResult<VenueRow | null>> {
		const segment = path.trim();
		return this.row(
			'LoadVenue',
			isUUID(segment)
				? this.client.from('venues').select().eq('id', segment).maybeSingle()
				: this.client.from('venues').select().eq('slug', segment.toLowerCase()).maybeSingle()
		);
	}

	/** Whether no venue holds this web address yet. Advisory: see `editVenueSlug`. */
	async isVenueAddressAvailable(slug: string): Promise<ReadResult<boolean>> {
		const { data, error } = await this.client
			.from('venues')
			.select('id')
			.eq('slug', slug.trim().toLowerCase())
			.maybeSingle();
		if (error) return { data: false, error: this.error('LoadVenue', error).error };
		return { data: data === null, error: undefined };
	}

	async getVenues(): Promise<ReadResult<VenueRow[] | null>> {
		return this.rows('LoadVenue', this.client.from('venues').select('*'));
	}

	async getVenuesByIDs(ids: VenueID[]): Promise<ReadResult<VenueRow[] | null>> {
		return this.rows('LoadVenue', this.client.from('venues').select().in('id', ids));
	}

	async getVenueRoles(venue: VenueID): Promise<ReadResult<RoleRow[] | null>> {
		return this.rows('LoadRole', this.client.from('roles').select('*').eq('venueid', venue));
	}

	/** How many tokens of the given currency the venue's reserve holds. A count
	 * rather than the rows: the dashboard and the gift form only ever wanted the
	 * number, and a reserve large enough to serve a community is far past the
	 * `max_rows` cap that silently truncated the array they used to count. */
	async getVenueTokenCount(
		venue: VenueID,
		currency: CurrencyID
	): Promise<ReadResult<number | null>> {
		return this.count(
			'LoadToken',
			this.client
				.from('tokens')
				.select('id', { count: 'exact', head: true })
				.eq('venue', venue)
				.eq('currency', currency)
		);
	}

	async getVenueSubmissions(venue: VenueID): Promise<ReadResult<SubmissionRow[] | null>> {
		return this.rows(
			'LoadSubmission',
			this.client.from('submissions').select('*').eq('venue', venue)
		);
	}

	async getVenueSubmissionExternalIDs(
		venue: VenueID
	): Promise<ReadResult<Pick<SubmissionRow, 'externalid'>[] | null>> {
		return this.rows(
			'LoadSubmission',
			this.client.from('submissions').select('externalid').eq('venue', venue)
		);
	}

	async getVenueSubmissionCount(venue: VenueID): Promise<ReadResult<number | null>> {
		return this.count(
			'LoadSubmission',
			this.client.from('submissions').select('*', { count: 'exact', head: true }).eq('venue', venue)
		);
	}

	async getVenueSubmissionTypes(venue: VenueID): Promise<ReadResult<SubmissionType[] | null>> {
		return this.rows(
			'LoadSubmissionType',
			this.client.from('submission_types').select('*').eq('venue', venue)
		);
	}

	async getVenueVolunteers(venue: VenueID): Promise<ReadResult<VenueVolunteer[] | null>> {
		return this.rows('LoadVolunteer', venueVolunteersQuery(this.client, venue));
	}

	async getVenueSettingsVolunteers(
		venue: VenueID
	): Promise<ReadResult<VenueSettingsVolunteer[] | null>> {
		return this.rows('LoadVolunteer', venueSettingsVolunteersQuery(this.client, venue));
	}

	async getVenueCommitments(venue: VenueID): Promise<ReadResult<VenueCommitment[] | null>> {
		return this.rows('LoadVolunteer', venueCommitmentsQuery(this.client, venue));
	}

	async getVenueAssignments(venue: VenueID): Promise<ReadResult<AssignmentRow[] | null>> {
		return this.rows(
			'LoadAssignment',
			this.client.from('assignments').select('*').eq('venue', venue)
		);
	}

	async getVenueSubmissionEditors(
		venue: VenueID
	): Promise<ReadResult<{ submission: SubmissionID; has_editor: boolean }[] | null>> {
		return this.rows(
			'LoadAssignment',
			this.client.rpc('venue_submission_editors', { _venue: venue })
		);
	}

	async getVenueActiveAssignmentScholars(
		venue: VenueID
	): Promise<ReadResult<Pick<AssignmentRow, 'scholar'>[] | null>> {
		return this.rows(
			'LoadAssignment',
			this.client
				.from('assignments')
				.select('scholar')
				.eq('venue', venue)
				.eq('approved', true)
				.eq('completed', false)
		);
	}

	async getVenuePreferenceLevels(venue: VenueID): Promise<ReadResult<PreferenceLevelRow[] | null>> {
		return this.rows(
			'LoadPreferenceLevel',
			this.client
				.from('preference_levels')
				.select('*')
				.eq('venueid', venue)
				.order('rank', { ascending: true })
		);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Proposals & supporters
	// ─────────────────────────────────────────────────────────────────────────

	async exportScholarData(scholar: ScholarID): Promise<Result<unknown>> {
		const { data, error } = await this.client.rpc('export_scholar_data', { _scholar: scholar });
		if (error)
			return this.error(
				rpcErrorKey(error, 'ExportScholarData', { RR006: 'NotYourAccount' }),
				error
			);
		return { data, error: undefined };
	}

	async eraseScholar(scholar: ScholarID): Promise<Result> {
		// Irreversible by design: the point is that the data is gone. The caller is
		// responsible for confirming intent and for signing the scholar out
		// afterwards — their session outlives the identity behind it.
		const { error } = await this.client.rpc('erase_scholar', { _scholar: scholar });
		if (error)
			return this.error(rpcErrorKey(error, 'EraseScholar', { RR006: 'NotYourAccount' }), error);
		return { error: undefined, data: undefined };
	}

	async setSteward(scholar: ScholarID, steward: boolean): Promise<Result<boolean>> {
		const { data, error } = await this.client.rpc('set_steward', {
			_scholar: scholar,
			_steward: steward
		});
		if (error)
			return this.error(
				rpcErrorKey(error, steward ? 'PromoteSteward' : 'DemoteSteward', {
					RR010: 'NotSteward',
					RR011: 'ScholarNotFound',
					RR012: 'LastSteward',
					RR013: 'CannotDemoteSelf'
				}),
				error
			);
		// `changed` distinguishes "we promoted them" from "they already were one",
		// which the RPC reports rather than raising.
		return { data: booleanField(data, 'changed') ?? false, error: undefined };
	}

	async addSteward(emailOrORCID: string): Promise<Result<ScholarID>> {
		const { data: id, error: findError } = await this.findScholar(emailOrORCID);
		if (id === undefined) return this.error('ScholarNotFound', findError?.details);

		// No client-side "are they already a steward?" test: addCurrencyMinter can
		// afford one because its caller already holds the array, but here the answer
		// comes back from the RPC, which is free of the check-then-write race.
		const { data: changed, error } = await this.setSteward(id, true);
		if (error) return { error };
		if (changed !== true) return this.error('AlreadySteward');
		return { data: id, error: undefined };
	}

	async proposeVenue(
		scholarid: ScholarID,
		title: string,
		url: string,
		editors: string[],
		currency: CurrencyID | null,
		minters: string[],
		census: number,
		message: string,
		paymentFree: boolean = false
	): Promise<Result<string>> {
		// Make a proposal
		// De-duplicated here rather than trusted from the form, because every writer of these
		// arrays owes the same guarantee: ProposalCreatedEditors sends one message per listed
		// address, so a doubled editor is invited twice.
		const { data, error: insertError } = await this.client
			.from('proposals')
			.insert({
				title,
				url,
				editors: dedupeAddresses(editors),
				census,
				currency,
				minters: dedupeAddresses(minters),
				payment_free: paymentFree
			})
			.select()
			.single();

		if (insertError || data === null) return this.error('CreateProposal', insertError);

		const proposalid = data.id;

		const { error } = await this.addVenueProposalSupporter(scholarid, proposalid, message);

		if (error) return { error };

		const notified: Notification[] = [];

		// Notify the stewards as a group, not individually. The shared inbox gives them one
		// thread they can assign and resolve between themselves; a per-steward fan-out gave
		// each of them a private copy and no way to see who had picked the proposal up.
		const stewardResult = await this.queueStewardEmail('ProposalCreatedStewards', [
			title,
			proposalid
		]);
		if (stewardResult.notified) notified.push(...stewardResult.notified);

		// Notify the proposal's editors. They are plain addresses rather than scholars, so
		// the RPC reads them back off the proposal row we just wrote instead of accepting
		// them here.
		const editorResult = await this.queueEmail('ProposalCreatedEditors', [title, proposalid], {
			proposal: proposalid
		});
		if (editorResult.notified) notified.push(...editorResult.notified);

		return { data: proposalid, notified };
	}

	async editVenueProposalTitle(venue: ProposalID, title: string): Promise<Result> {
		return this.updateProposal(venue, { title }, 'EditProposalTitle');
	}

	async editVenueProposalCensus(venue: ProposalID, census: number): Promise<Result> {
		return this.updateProposal(venue, { census }, 'EditProposalCensus');
	}

	async editVenueProposalEditors(venue: ProposalID, editors: string[]): Promise<Result> {
		return this.updateProposal(venue, { editors: dedupeAddresses(editors) }, 'EditProposalEditors');
	}

	async editVenueProposalMinters(venue: ProposalID, minters: string[]): Promise<Result> {
		return this.updateProposal(venue, { minters: dedupeAddresses(minters) }, 'EditProposalMinters');
	}

	async editVenueProposalURL(venue: ProposalID, url: string): Promise<Result> {
		return this.updateProposal(venue, { url }, 'EditProposalURL');
	}

	async deleteVenueProposal(proposal: ProposalID): Promise<Result> {
		const { error } = await this.client.from('proposals').delete().eq('id', proposal);
		if (error) return this.error('DeleteProposal');
		else return {};
	}

	async approveVenueProposal(proposal: ProposalID): Promise<Result<string>> {
		// Provisioning the venue — its currency (if none was proposed), the venue
		// itself, the editor role, the editor volunteers, the default submission
		// type, and the default compensation — plus linking the proposal to the
		// new venue, all happen atomically inside the approve_venue_proposal RPC.
		// A partial failure can no longer orphan any of those records. The
		// notification emails are dispatched here from the ids the RPC returns.
		const { data, error } = await this.client.rpc('approve_venue_proposal', {
			_proposal_id: proposal
		});
		// RR014 is the one refusal a steward can act on: none of the proposed editors have
		// accounts, so there is nobody to administer the venue. Everything else is genuinely
		// "couldn't create the venue".
		if (error)
			return this.error(
				rpcErrorKey(error, 'ApproveProposalNoVenue', { RR014: 'ApproveProposalNoScholars' }),
				error
			);

		const venueID = stringField(data, 'venue_id');
		const editorIDs = stringArrayField(data, 'editor_ids');
		const supporterIDs = stringArrayField(data, 'supporter_ids');
		const title = stringField(data, 'title');
		if (venueID === null || editorIDs === null || supporterIDs === null || title === null)
			return this.error('ApproveProposalNoVenue');

		const scholarsToEmail = [...editorIDs, ...supporterIDs];
		const emailResult = await this.emailScholars(scholarsToEmail, 'VenueApproved', [
			title,
			await this.venuePathOf(venueID)
		]);

		return { data: venueID, notified: emailResult.notified };
	}

	async addVenueProposalSupporter(
		scholarid: ScholarID,
		proposalid: ProposalID,
		message: string
	): Promise<Result> {
		// Make the first supporter
		const { error } = await this.client
			.from('supporters')
			.insert({ proposalid, scholarid, message });

		if (error) return this.error('CreateSupporter', error);
		else return {};
	}

	async editVenueProposalSupport(support: SupporterID, message: string): Promise<Result> {
		const { error } = await this.client.from('supporters').update({ message }).eq('id', support);
		return this.errorOrEmpty('EditSupport', error);
	}

	async deleteVenueProposalSupport(support: SupporterID): Promise<Result> {
		const { error } = await this.client.from('supporters').delete().eq('id', support);
		if (error) return this.error('RemoveSupport', error);
		else return {};
	}

	async getProposal(id: ProposalID): Promise<ReadResult<ProposalRow | null>> {
		return this.row(
			'LoadProposal',
			this.client.from('proposals').select().eq('id', id).maybeSingle()
		);
	}

	async getUnassignedProposals(): Promise<ReadResult<ProposalRow[] | null>> {
		return this.rows('LoadProposal', this.client.from('proposals').select().is('venue', null));
	}

	async getProposalSupporters(
		proposal: ProposalID
	): Promise<ReadResult<ProposalSupporter[] | null>> {
		return this.rows('LoadProposal', proposalSupportersQuery(this.client, proposal));
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Currencies & tokens
	// ─────────────────────────────────────────────────────────────────────────

	async updateCurrencyName(id: CurrencyID, name: string): Promise<Result> {
		return this.updateCurrency(id, { name }, 'UpdateCurrencyName');
	}

	async updateCurrencyDescription(id: CurrencyID, description: string) {
		return this.updateCurrency(id, { description }, 'UpdateCurrencyDescription');
	}

	async editCurrencyMinters(id: CurrencyID, minters: string[]): Promise<Result> {
		return this.updateCurrency(id, { minters }, 'EditCurrencyMinters');
	}

	async addCurrencyMinter(
		id: CurrencyID,
		minters: string[],
		emailOrORCID: string
	): Promise<Result> {
		const { data: scholarID, error: scholarError } = await this.findScholar(emailOrORCID);
		if (scholarID === undefined) return this.error('ScholarNotFound', scholarError?.details);

		if (minters.includes(scholarID)) return this.error('AlreadyMinter');

		return this.editCurrencyMinters(id, Array.from(new Set([...minters, scholarID])));
	}

	async mintTokens(
		creator: ScholarID,
		currencyID: CurrencyID,
		amount: number,
		to: VenueID,
		/** Why are these tokens being minted? */
		purpose: string
	): Promise<Result<TokenID[]>> {
		// Minting the tokens into the venue reserve and recording the approved
		// mint transaction happen atomically inside the mint_tokens RPC.
		const { data, error } = await this.client.rpc('mint_tokens', {
			_currency: currencyID,
			_amount: amount,
			_to_venue: to,
			_purpose: purpose
		});
		if (error) return this.error('MintTokens', error);

		const tokenIDs = stringArrayField(data, 'token_ids');
		if (tokenIDs === null) return this.error('MintTokens');
		return { data: tokenIDs };
	}

	async getCurrency(id: CurrencyID): Promise<ReadResult<CurrencyRow | null>> {
		return this.row(
			'LoadCurrency',
			this.client.from('currencies').select().eq('id', id).maybeSingle()
		);
	}

	async getCurrencies(): Promise<ReadResult<CurrencyRow[] | null>> {
		return this.rows('LoadCurrency', this.client.from('currencies').select('*'));
	}

	async getCurrenciesByIDs(ids: CurrencyID[]): Promise<ReadResult<CurrencyRow[] | null>> {
		return this.rows('LoadCurrency', this.client.from('currencies').select('*').in('id', ids));
	}

	async getCurrencyVenues(currency: CurrencyID): Promise<ReadResult<VenueRow[] | null>> {
		return this.rows('LoadVenue', this.client.from('venues').select().eq('currency', currency));
	}

	/** Total supply of a currency, and how many scholars and venues hold any of
	 * it. The currency page used to download every token row in the currency and
	 * compute all three in the browser with `.length` and two `Set`s — so past a
	 * thousand tokens it reported 1000, and holder counts drawn from an arbitrary
	 * sample of them. Three SQL aggregates in one round trip. */
	async getCurrencyHolderCounts(
		currency: CurrencyID
	): Promise<ReadResult<CurrencyHolderCounts | null>> {
		const { data, error } = await this.client.rpc('currency_holder_counts', {
			_currency: currency
		});
		if (error) {
			this.error('LoadToken', error);
			return { data: null };
		}
		return { data: data as unknown as CurrencyHolderCounts };
	}

	async getTokenBalances(
		currency: CurrencyID,
		scholarIDs: ScholarID[]
	): Promise<ReadResult<TokenBalance[] | null>> {
		// Short-circuit rather than sending an empty array: there is nothing to
		// group, and every caller treats a missing scholar as a zero balance.
		if (scholarIDs.length === 0) return { data: [] };
		return this.rows(
			'LoadToken',
			this.client.rpc('scholar_balances', { _currency: currency, _scholars: scholarIDs })
		);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Roles
	// ─────────────────────────────────────────────────────────────────────────

	/** Goes through the RPC rather than a plain insert so the new role gets a priority of
	 * its own. `roles.priority` defaults to 0, and priority 0 is what the database checks
	 * when deciding who acts as an editor, so inserting directly made every new role an
	 * editor role. The RPC runs as the caller, so the venue-admin insert policy still
	 * applies. */
	async createRole(id: VenueID, name: string, description: string = ''): Promise<Result<RoleRow>> {
		const { data, error } = await this.client.rpc('create_role', {
			_venue: id,
			_name: name,
			_description: description
		});
		if (error) return this.error('CreateRole', error);
		else return { data };
	}

	async editRoleName(id: RoleID, name: string) {
		return this.updateRole(id, { name }, 'UpdateRoleName');
	}

	async editRoleDescription(id: RoleID, description: string) {
		return this.updateRole(id, { description }, 'UpdateRoleDescription');
	}

	async editRoleInvited(id: RoleID, on: boolean) {
		return this.updateRole(id, { invited: on }, 'UpdateRoleInvited');
	}

	async editRoleBidding(id: RoleID, biddable: boolean) {
		return this.updateRole(id, { biddable }, 'EditRoleBidding');
	}

	async editRoleAnonymousAuthors(id: RoleID, anonymous: boolean): Promise<Result> {
		return this.updateRole(id, { anonymous_authors: anonymous }, 'EditRoleAnonymousAuthors');
	}

	async editRoleDesiredAssignments(id: RoleID, desiredAssignments: number) {
		return this.updateRole(
			id,
			{ desired_assignments: desiredAssignments },
			'EditRoleDesiredAssignments'
		);
	}

	async editRoleApprover(id: RoleID, approver: RoleID | null) {
		return this.updateRole(id, { approver }, 'EditRoleApprover');
	}

	async reorderRole(role: RoleRow, roles: RoleRow[], direction: -1 | 1) {
		const sorted = roles.toSorted((a, b) => a.priority - b.priority);
		const index = sorted.findIndex((r) => r.id === role.id);

		if (index === -1) return this.error('ReorderRole');

		const target = index + direction;
		if (target < 0 || target >= sorted.length) return {};

		[sorted[index], sorted[target]] = [sorted[target], sorted[index]];

		for (const [i, r] of sorted.entries()) {
			const { error } = await this.client.from('roles').update({ priority: i }).eq('id', r.id);
			if (error) return this.error('ReorderRole', error);
		}

		return {};
	}

	async deleteRole(id: RoleID) {
		const { error } = await this.client.from('roles').delete().eq('id', id);
		return this.errorOrEmpty('DeleteRole', error);
	}

	async getRolesByApprover(roleIDs: RoleID[]): Promise<ReadResult<RoleRow[] | null>> {
		return this.rows('LoadRole', this.client.from('roles').select('*').in('approver', roleIDs));
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Submissions & submission types
	// ─────────────────────────────────────────────────────────────────────────

	async verifyCharges(
		charges: Charge[],
		currency: CurrencyID
	): Promise<Result<true | ChargeCoverage[] | undefined>> {
		// First, find the scholars with the specified ORCIDs.
		const { data: scholars, error: scholarsError } = await this.convertORCIDsToScholars(
			charges.map((charge) => charge.scholar)
		);

		if (scholarsError) return { error: scholarsError };

		// Find the scholars that weren't found.
		if (scholars === undefined) return { data: undefined };
		if (scholars.length < charges.length)
			return {
				data: charges.map((charge) => ({
					scholar: charge.scholar,
					// Resolvable but unchecked, versus not a scholar at all. The caller
					// reports the latter separately, so it must stay distinguishable.
					covered: scholars.some((s) => s.orcid === charge.scholar) ? true : undefined
				}))
			};

		// Answered in the database, per author, as a yes/no — IN THIS VENUE'S
		// CURRENCY. The currency filter is not optional: a balance is meaningless
		// without one, and counting a scholar's holdings across all currencies made
		// this disagree with the create_submission RPC that ultimately decides, so
		// the check passed and the submission was then rejected with RR003.
		//
		// A yes/no rather than the balances themselves, because balances are private
		// (#109) and co-authorship puts nobody in the audience for anybody's. It also
		// keeps working: scholar_balances would rightly return the submitter nothing
		// about their co-authors, and this would then report every one of them as
		// unable to pay. The form never showed the number — only who was short.
		const resolvable = charges
			.map((charge) => ({
				charge,
				id: scholars.find((scholar) => scholar.orcid === charge.scholar)?.id
			}))
			.filter((entry): entry is { charge: Charge; id: ScholarID } => entry.id !== undefined)
			.filter((entry) => entry.charge.payment !== undefined);

		const { data: coverage, error } = await this.client.rpc('authors_can_cover', {
			_currency: currency,
			_scholars: resolvable.map((entry) => entry.id),
			_amounts: resolvable.map((entry) => entry.charge.payment as number)
		});
		if (error) {
			this.error('LoadToken', error);
			return { error: { message: 'Missing token' } };
		}

		const covered = new Map(coverage.map((row) => [row.scholar, row.covered]));

		const results: ChargeCoverage[] = charges.map((charge) => {
			const scholarID = scholars.find((scholar) => scholar.orcid === charge.scholar)?.id;
			return {
				scholar: charge.scholar,
				// Unresolvable scholar, or a charge with no amount: nothing to check.
				covered:
					scholarID === undefined || charge.payment === undefined
						? undefined
						: (covered.get(scholarID) ?? false)
			};
		});

		if (results.some((result) => result.covered !== true)) return { data: results };

		// Otherwise, all is good.
		return { data: true };
	}

	async createSubmission(
		creator: ScholarID,
		title: string,
		expertise: string,
		venue: VenueID,
		externalID: string,
		previousID: string | null,
		previous: SubmissionID | null,
		submission_type: SubmissionTypeID,
		charges: Charge[],
		note: string | null
	): Promise<Result<SubmissionID>> {
		// Verify charges (reads) and resolve author ORCIDs to scholar ids before
		// the atomic write. The create_submission RPC then records every proposed
		// payment, immediately approves the submitter's own charge (moving their
		// tokens to the venue), and inserts the submission in a single
		// transaction — so a connectivity loss can't orphan proposed
		// transactions or violate the submission's array-cardinality constraints.
		// Charges are denominated in the venue's currency, so read it from the venue
		// rather than accepting it as an argument — that way the currency the
		// balances are checked against cannot drift from the venue being submitted
		// to, which is the same currency create_submission will use.
		const { data: venueRow, error: venueError } = await this.client
			.from('venues')
			.select('id, currency, title, admins, slug')
			.eq('id', venue)
			.single();
		if (venueError) return this.error('LoadVenue', venueError);

		const chargeError = await this.verifyCharges(charges, venueRow.currency);
		if (chargeError.error) return { error: chargeError.error };
		if (chargeError.data !== true) return { error: { message: this.locale.error.InvalidCharges } };

		const { data: scholars, error: scholarsError } = await this.convertORCIDsToScholars(
			charges.map((charge) => charge.scholar)
		);
		if (scholarsError || scholars === undefined)
			return {
				error: { message: this.locale.error.ScholarNotFound, details: scholarsError?.details }
			};

		// Resolve the author id for each charge, preserving order.
		const authors = charges
			.map((charge) => scholars.find((s) => s.orcid === charge.scholar)?.id)
			.filter((a): a is ScholarID => a !== undefined);
		if (authors.length < charges.length)
			return { error: { message: this.locale.error.MissingSubmissionCharge } };

		// Supabase's type generator types every function argument as non-null,
		// but these columns are genuinely nullable (no predecessor, no note) and
		// Postgres accepts NULL at runtime — so cast the nullable args through.
		const { data, error } = await this.client.rpc('create_submission', {
			_venue: venue,
			_external_id: externalID,
			_previous_id: previousID as string,
			_previous: previous as string,
			_submission_type: submission_type,
			_authors: authors,
			_payments: charges.map((charge) => charge.payment ?? 0),
			_title: title,
			_expertise: expertise,
			_note: note as string,
			_purpose: `Payment for submission ${externalID}`
		});
		if (error)
			return this.error(
				rpcErrorKey(error, 'NewSubmission', {
					RR003: 'TransferTokensInsufficient',
					RR009: 'SubmissionNotAuthor'
				}),
				error
			);

		const submissionID = stringField(data, 'submission_id');
		if (submissionID === null) return { error: { message: this.locale.error.NewSubmission } };

		// Tell each charged co-author that a proposed charge awaits their
		// approval — the submitter's own charge already settled in the RPC, and
		// without this email a co-author would only discover the charge by
		// visiting their dashboard. Per-recipient, since each charge differs.
		const notifications: Notification[] = [];
		const submissionTitle = title.trim() ? title : externalID;
		for (const [index, author] of authors.entries()) {
			const payment = charges[index]?.payment ?? 0;
			if (author === creator || payment === 0) continue;
			const emailResult = await this.emailScholars([author], 'SubmissionCharged', [
				submissionTitle,
				venueRow.title,
				payment.toString(),
				author
			]);
			if (emailResult.notified) notifications.push(...emailResult.notified);
		}

		// Tell the venue's editors that a submission arrived. The RPC seats the venue's
		// sole editor when there is exactly one and reports who; otherwise nobody is
		// editing it yet and somebody has to pick it up — the step that previously had no
		// prompt at all, which is how a submission could sit unnoticed indefinitely.
		const editor = stringField(data, 'editor');
		const editorResult =
			editor !== null
				? await this.emailScholars([editor], 'SubmissionAssignedEditor', [
						submissionTitle,
						venueRow.title,
						venuePath(venueRow),
						submissionID
					])
				: await this.emailEditorsOf(venue, venueRow.admins, 'SubmissionNeedsEditor', [
						submissionTitle,
						venueRow.title,
						venuePath(venueRow),
						submissionID
					]);
		if (editorResult.notified) notifications.push(...editorResult.notified);

		return { data: submissionID, notified: notifications };
	}

	/**
	 * Email the people who can act on a submission that has no editor: the venue's
	 * editors, and its admins.
	 *
	 * Both, because after `can_claim_editor_role` either can do something about it — an
	 * editor by claiming it, an admin by assigning someone to the role. Before that
	 * policy existed only admins could, which is why notifying the editors would have
	 * been mail nobody could act on.
	 */
	private async emailEditorsOf(
		venue: VenueID,
		admins: ScholarID[],
		template: EmailType,
		args: string[]
	): Promise<Result> {
		const { data: roles } = await this.client
			.from('roles')
			.select('id')
			.eq('venueid', venue)
			.eq('priority', 0);
		const roleIDs = (roles ?? []).map((role) => role.id);
		const { data: volunteers } =
			roleIDs.length === 0
				? { data: [] }
				: await this.client
						.from('volunteers')
						.select('scholarid')
						.in('roleid', roleIDs)
						.eq('active', true)
						.eq('accepted', 'accepted');
		const recipients = [...new Set([...(volunteers ?? []).map((v) => v.scholarid), ...admins])];
		if (recipients.length === 0) return {};
		return this.emailScholars(recipients, template, args);
	}

	async bulkImportSubmissions(
		venue: VenueID,
		submissions: ImportedSubmission[],
		importNote: string | null
	): Promise<Result<BulkImportResult>> {
		const payload = submissions.map((s) => ({
			title: s.title,
			externalid: s.externalID,
			previousid: s.previousID,
			expertise: s.expertise,
			submission_type: s.submission_type,
			note: s.note,
			// Entry keys are the RPC's own, so this passes through as it is.
			people: s.people
		}));

		const { data, error } = await this.client.rpc('bulk_import_submissions', {
			_venueid: venue,
			_submissions: payload,
			_import_note: importNote ?? ''
		});

		if (error) {
			return { error: { message: this.locale.error.BulkImportSubmissions, details: error } };
		}

		const result = data as {
			submission_ids: SubmissionID[];
			transaction_id: TransactionID | null;
			mint_amount: number;
			editor: ScholarID | null;
			seated: number;
			seated_by: Record<ScholarID, number> | null;
			waiting: number;
		};

		const imported = result.submission_ids?.length ?? 0;
		const seatedBy = result.seated_by ?? {};

		// One digest per person rather than one message per row: an import of two hundred
		// manuscripts is one piece of news, not two hundred. Each scholar the import seated
		// is told how many submissions they now hold -- which may be one editor seated on
		// every row, or a dozen associate editors each holding a few -- and the venue's
		// editors and admins are told about whatever was left for somebody to claim.
		const notifications: Notification[] = [];
		if (imported > 0) {
			const { data: venueRow } = await this.client
				.from('venues')
				.select('id, title, admins, slug')
				.eq('id', venue)
				.single();
			if (venueRow !== null) {
				for (const [scholar, count] of Object.entries(seatedBy)) {
					const seatedResult = await this.emailScholars([scholar], 'SubmissionsAssignedEditor', [
						count.toString(),
						venueRow.title,
						venuePath(venueRow)
					]);
					if (seatedResult.notified) notifications.push(...seatedResult.notified);
				}

				// Only when something is actually waiting. Telling a venue that zero
				// submissions need an editor is noise.
				const unseated = result.waiting ?? 0;
				if (unseated > 0) {
					const waitingResult = await this.emailEditorsOf(
						venue,
						venueRow.admins,
						'SubmissionsNeedEditors',
						[unseated.toString(), venueRow.title, venuePath(venueRow)]
					);
					if (waitingResult.notified) notifications.push(...waitingResult.notified);
				}
			}
		}

		return {
			data: {
				submissionIDs: result.submission_ids ?? [],
				transactionID: result.transaction_id,
				mintAmount: result.mint_amount,
				seatedBy
			},
			notified: notifications
		};
	}

	async updateSubmissionType(
		submissionID: SubmissionID,
		submissionTypeID: SubmissionTypeID
	): Promise<Result> {
		return this.updateSubmission(
			submissionID,
			{ submission_type: submissionTypeID },
			'UpdateSubmissionType'
		);
	}

	async updateSubmissionExpertise(
		submissionID: SubmissionID,
		expertise: string | null
	): Promise<Result> {
		return this.updateSubmission(submissionID, { expertise }, 'UpdateSubmissionExpertise');
	}

	async updateSubmissionTitle(submissionID: SubmissionID, title: string): Promise<Result> {
		return this.updateSubmission(submissionID, { title }, 'UpdateSubmissionTitle');
	}

	async updateSubmissionNote(submissionID: SubmissionID, note: string | null): Promise<Result> {
		return this.updateSubmission(submissionID, { note }, 'UpdateSubmissionNote');
	}

	async markSubmissionDone(submissionID: SubmissionID): Promise<Result<MarkSubmissionDoneOutcome>> {
		// Authorization, blocker validation, atomic compensation of every
		// uncompleted priority-0 editor assignment, and the status flip all
		// happen inside the mark_submission_done RPC. The application layer
		// surfaces the structured outcome and dispatches notifications.
		const { data, error } = await this.client.rpc('mark_submission_done', {
			_submission_id: submissionID,
			_payment_purpose_template: this.locale.view.transactions.purposeTemplate.compensation,
			_mint_purpose_template: this.locale.view.transactions.purposeTemplate.mint
		});
		if (error) return this.error('MarkSubmissionDoneRPC', error);
		if (!isMarkSubmissionDoneResult(data)) return this.error('MarkSubmissionDoneRPC');

		if (data.status === 'blocked') {
			return { data: { status: 'blocked', blockers: data.blockers } };
		}

		if (data.status === 'insufficient') {
			// The RPC recorded a single proposed mint covering the total
			// shortfall across all editor payouts. Email the venue's
			// minter(s) so they can approve it; the editor must then retry.
			const { data: currency } = await this.client
				.from('currencies')
				.select('minters')
				.eq('id', data.currency_id)
				.single();
			if (currency !== null && currency.minters.length > 0) {
				await this.emailScholars(currency.minters, 'VenueOutOfTokens', [
					data.total_amount.toString(),
					'editor',
					data.shortfall.toString(),
					await this.venuePathOf(data.venue_id),
					data.venue_title
				]);
			}
			return {
				data: {
					status: 'insufficient',
					shortfall: data.shortfall,
					total_amount: data.total_amount
				}
			};
		}

		// Tokens have moved and the submission is done. Email each editor
		// individually with their actual payout amount and role, so each
		// gets a per-recipient banner via handle().
		const notifications: Notification[] = [];
		// Resolved once rather than per payout: every message in this loop is about the same
		// venue.
		const donePath = await this.venuePathOf(data.venue_id);
		for (const payout of data.payouts) {
			const result = await this.emailScholars([payout.scholar_id], 'WorkCompensated', [
				payout.role_name,
				payout.amount.toString(),
				donePath,
				data.submission_id
			]);
			if (result.notified) notifications.push(...result.notified);
		}

		return {
			data: {
				status: 'completed',
				total_amount: data.total_amount,
				recipients: data.payouts.map((p) => p.scholar_id)
			},
			notified: notifications
		};
	}

	async createSubmissionType(
		venue: VenueID,
		name: string,
		description: string,
		revision_of: SubmissionTypeID | null,
		cost: number = 0
	): Promise<Result<SubmissionType>> {
		const { data, error } = await this.client
			.from('submission_types')
			.insert({ venue, name, description, revision_of, submission_cost: cost })
			.select()
			.single();

		if (error) return this.error('CreateSubmissionType', error);
		return { data };
	}

	async editSubmissionType(
		id: SubmissionTypeID,
		name: string,
		description: string,
		revision_of: SubmissionTypeID | null
	): Promise<Result> {
		const { error } = await this.client
			.from('submission_types')
			.update({ name, description, revision_of })
			.eq('id', id);

		if (error) return this.error('EditSubmissionType', error);
		return { data: undefined };
	}

	async editSubmissionTypeCost(id: SubmissionTypeID, cost: number): Promise<Result> {
		const { error } = await this.client
			.from('submission_types')
			.update({ submission_cost: cost })
			.eq('id', id);

		if (error) return this.error('EditSubmissionTypeCost', error);
		return { data: undefined };
	}

	async deleteSubmissionType(id: SubmissionTypeID): Promise<Result> {
		const { error } = await this.client.from('submission_types').delete().eq('id', id);
		return this.errorOrEmpty('DeleteSubmissionType', error);
	}

	async getSubmission(id: SubmissionID): Promise<ReadResult<SubmissionRow | null>> {
		return this.row(
			'LoadSubmission',
			this.client.from('submissions').select('*').eq('id', id).maybeSingle()
		);
	}

	async getPreviousSubmissionByID(id: SubmissionID): Promise<ReadResult<SubmissionRow[] | null>> {
		return this.rows('LoadSubmission', this.client.from('submissions').select('*').eq('id', id));
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Thanks (#22): author thank-you notes to reviewers
	// ─────────────────────────────────────────────────────────────────────────

	/** Fan a rendered thank-you email out to an audience the caller may not be
	 * able to see (queue_thanks_emails resolves recipients server-side to keep
	 * reviewers anonymous). Best-effort: a failure here doesn't undo the note's
	 * state change, matching the rest of the email pipeline. */
	private async queueThanksEmails(
		thanksID: ThanksID,
		audience: 'recipients' | 'vetters' | 'author',
		template: EmailType,
		args: string[]
	) {
		const { subject, message } = renderEmail(template, args);
		await this.client.rpc('queue_thanks_emails', {
			_thanks_id: thanksID,
			_audience: audience,
			_subject: subject,
			_message: message
		});
	}

	async proposeThanks(
		submission: SubmissionID,
		message: string
	): Promise<Result<{ status: ThanksStatus }>> {
		// The RPC validates (author + done submission) and records the note,
		// returning the resolved status (proposed, or approved when the venue has
		// vetting off). Notification copy is rendered here from the shared
		// template registry, then fanned out server-side to preserve anonymity.
		const { data, error } = await this.client.rpc('propose_thanks', {
			_submission: submission,
			_message: message
		});
		if (error) return this.error('ProposeThanks', error);
		const status = (stringField(data, 'status') as ThanksStatus | null) ?? 'proposed';
		const thanksID = stringField(data, 'thanks_id');
		const venue = stringField(data, 'venue');
		if (thanksID && venue) {
			const path = await this.venuePathOf(venue);
			if (status === 'approved')
				await this.queueThanksEmails(thanksID, 'recipients', 'ThanksReceived', [
					message,
					path,
					submission
				]);
			else
				await this.queueThanksEmails(thanksID, 'vetters', 'ThanksPendingReview', [
					path,
					submission
				]);
		}
		return { error: undefined, data: { status } };
	}

	async approveThanks(id: ThanksID): Promise<Result<undefined>> {
		// The RPC authorizes (venue admin / editor) and flips the note to approved,
		// returning the venue, submission, and note text so we can render and
		// deliver the note to its (server-resolved) reviewers.
		const { data, error } = await this.client.rpc('approve_thanks', { _id: id });
		if (error) return this.error('ApproveThanks', error);
		const venue = stringField(data, 'venue');
		const submission = stringField(data, 'submission');
		const note = stringField(data, 'message');
		if (venue && submission && note !== null)
			await this.queueThanksEmails(id, 'recipients', 'ThanksReceived', [
				note,
				await this.venuePathOf(venue),
				submission
			]);
		return { error: undefined, data: undefined };
	}

	async declineThanks(id: ThanksID, reason: string): Promise<Result<undefined>> {
		const { data, error } = await this.client.rpc('decline_thanks', { _id: id, _reason: reason });
		if (error) return this.error('DeclineThanks', error);
		const venue = stringField(data, 'venue');
		const submission = stringField(data, 'submission');
		if (venue && submission)
			await this.queueThanksEmails(id, 'author', 'ThanksDeclined', [
				reason,
				await this.venuePathOf(venue),
				submission
			]);
		return { error: undefined, data: undefined };
	}

	async getSubmissionThanks(submission: SubmissionID): Promise<ReadResult<ThanksRow[] | null>> {
		// RLS returns only what the viewer may see: the author's own notes, all
		// notes for a vetter, and approved notes for a recipient reviewer.
		return this.rows(
			'LoadThanks',
			this.client
				.from('thanks')
				.select('*')
				.eq('submission', submission)
				.order('created_at', { ascending: true })
		);
	}

	async getPreviousSubmissionByExternalID(
		venue: VenueID,
		externalID: string
	): Promise<ReadResult<SubmissionRow[] | null>> {
		return this.rows(
			'LoadSubmission',
			this.client.from('submissions').select('*').eq('venue', venue).eq('externalid', externalID)
		);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Compensation
	// ─────────────────────────────────────────────────────────────────────────

	async createCompensation(
		submission_type: SubmissionTypeID,
		role: RoleID,
		amount: number,
		rationale: string
	): Promise<Result<CompensationRow>> {
		const { data, error } = await this.client
			.from('compensation')
			.insert({ submission_type, role, amount, rationale })
			.select()
			.single();

		if (error) return this.error('CreateCompensation', error);
		return { data };
	}

	async editCompensation(
		submission_type: SubmissionTypeID,
		role: RoleID,
		amount: number | null,
		rationale: string
	): Promise<Result> {
		const { error } = await this.client
			.from('compensation')
			.upsert({ submission_type, role, amount, rationale })
			.select()
			.single();

		if (error) return this.error('EditCompensation', error);
		return { data: undefined };
	}

	async requestCompensation(
		scholarID: ScholarID,
		venueID: VenueID,
		externalManuscriptID: string,
		roleID: RoleID,
		note: string
	): Promise<Result> {
		// Is there a submission that this scholar can view with this manuscript ID?
		const { data: submissionData, error: submissionError } = await this.client
			.from('submissions')
			.select()
			.eq('externalid', externalManuscriptID);

		if (submissionData === null || submissionData.length === 0)
			return this.error('CompensationSubmissionNotFound', submissionError);

		const submission = submissionData[0];

		// Is there an assignment for this scholar, venue, role, and submission?
		const { data: assignmentData, error: assignmentError } = await this.client
			.from('assignments')
			.select()
			.eq('scholar', scholarID)
			.eq('venue', venueID)
			.eq('role', roleID)
			.eq('submission', submission.id);

		if (assignmentError) return this.error('CompensationAssignmentCheck', assignmentError);

		if (assignmentData.length === 0) {
			const result = await this.createAssignment(submission.id, scholarID, roleID, false, false);
			if (result.error) return result;
		}

		// Stamp the request on the assignment (the scholar's own row, which the
		// assignments UPDATE policy permits). The stamp is what lets the daily
		// remind function nag approvers about finished work awaiting compensation
		// without nagging them about reviews still in progress.
		const { error: stampError } = await this.client
			.from('assignments')
			.update({ compensation_requested_at: new Date().toISOString() })
			.eq('scholar', scholarID)
			.eq('venue', venueID)
			.eq('role', roleID)
			.eq('submission', submission.id);
		if (stampError) return this.error('CompensationAssignmentCheck', stampError);

		// Notify whoever can act on this request, not the requester themselves.
		// "Can act on it" is exactly canApproveAssignment.ts — the same three
		// branches, unioned, rather than the near-miss this used to be. It
		// previously omitted the priority-0 editor branch entirely, and treated
		// admins as a fallback consulted only when no approver was assigned, so
		// the two people most able to act on a request were often the two who
		// never heard about it.
		const recipients = new Set<ScholarID>();

		const { data: roles, error: rolesError } = await this.client
			.from('roles')
			.select('id, priority, approver')
			.eq('venueid', venueID);
		if (rolesError) return this.error('CompensationAssignmentCheck', rolesError);

		const { data: submissionAssignments, error: approverError } = await this.client
			.from('assignments')
			.select('scholar, role')
			.eq('submission', submission.id)
			.eq('approved', true);
		if (approverError) return this.error('CompensationAssignmentCheck', approverError);

		const requestedRole = roles?.find((r) => r.id === roleID) ?? null;
		const editorRoleIDs = new Set((roles ?? []).filter((r) => r.priority === 0).map((r) => r.id));

		for (const a of submissionAssignments ?? []) {
			// Branch 2: the priority-0 editor of this submission approves any role.
			if (editorRoleIDs.has(a.role)) recipients.add(a.scholar);
			// Branch 3: whoever holds the role that approves the requested role.
			if (requestedRole?.approver !== null && a.role === requestedRole?.approver)
				recipients.add(a.scholar);
		}

		// Branch 1: venue admins can always approve, so they are always notified —
		// a union member, not a fallback.
		const { data: adminVenue, error: adminVenueError } = await this.client
			.from('venues')
			.select('admins')
			.eq('id', venueID)
			.single();
		if (adminVenueError) return this.error('CompensationAssignmentCheck', adminVenueError);
		for (const admin of adminVenue.admins) recipients.add(admin);

		// A scholar cannot action their own request, so never mail it to them.
		recipients.delete(scholarID);

		// No one left to notify — possible when the requester is the venue's only
		// admin. Don't error: the assignment was still created.
		if (recipients.size === 0) return { data: undefined, error: undefined };

		return this.emailScholars([...recipients], 'CompensationRequested', [
			await this.venuePathOf(venueID),
			submission.id,
			note
		]);
	}

	async getCompensationByTypes(
		typeIDs: SubmissionTypeID[]
	): Promise<ReadResult<CompensationRow[] | null>> {
		return this.rows(
			'LoadCompensation',
			this.client.from('compensation').select('*').in('submission_type', typeIDs)
		);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Volunteers & invitations
	// ─────────────────────────────────────────────────────────────────────────

	async createVolunteer(
		inviter: ScholarID,
		scholarid: ScholarID,
		roleid: RoleID,
		accepted: boolean,
		compensate: boolean,
		papers: number | null
	): Promise<Result<string>> {
		// Creating the volunteer record and, when this is the scholar's first
		// role at the role's venue and compensation is requested, settling the
		// welcome grant both happen atomically inside the create_volunteer RPC,
		// so the volunteer can never exist without its welcome grant (or vice
		// versa).
		const { data, error } = await this.client.rpc('create_volunteer', {
			_scholarid: scholarid,
			_roleid: roleid,
			_accepted: accepted,
			_compensate: compensate,
			// Nullable in Postgres ("unspecified"), but typed non-null by the generator.
			_papers: papers as number
		});
		if (error)
			return this.error(
				rpcErrorKey(error, 'CreateVolunteer', { RR004: 'AlreadyVolunteered' }),
				error
			);

		const volunteerID = stringField(data, 'volunteer_id');
		if (volunteerID === null) return this.error('CreateVolunteer');

		// Report the welcome grant the RPC actually made. Whether one happened
		// depends on whether this is the scholar's first role at this venue, the
		// venue's payment_free flag, and its welcome_amount — so the amount comes
		// back from the database rather than being guessed here.
		const granted = numberField(data, 'welcome_granted') ?? 0;
		return {
			data: volunteerID,
			notified: [
				{
					message:
						granted > 0
							? this.locale.notification.volunteeredWithTokens.replace(
									'{amount}',
									granted.toString()
								)
							: this.locale.notification.volunteered
				}
			]
		};
	}

	async updateVolunteerActive(id: VolunteerID, active: boolean): Promise<Result> {
		return this.updateVolunteer(id, { active }, 'UpdateVolunteerActive');
	}

	async updateVolunteerExpertise(id: VolunteerID, expertise: string): Promise<Result> {
		return this.updateVolunteer(id, { expertise }, 'UpdateVolunteerExpertise');
	}

	async updateVolunteerPapers(id: VolunteerID, papers: number | null): Promise<Result> {
		return this.updateVolunteer(id, { papers }, 'UpdateVolunteerPapers');
	}

	async inviteToRole(
		inviter: ScholarID,
		role: RoleRow,
		venue: VenueRow,
		emailsOrORCIDs: string[]
	): Promise<Result<string[]>> {
		const { data: scholars, error: scholarsError } = await this.client
			.from('scholars')
			.select()
			.or(
				'email.in.(' +
					emailsOrORCIDs.map((e) => `"${e}"`).join(',') +
					'), orcid.in.(' +
					emailsOrORCIDs.map((e) => `"${e}"`).join(',') +
					')'
			);
		if (scholarsError) return this.error('InviteToRole', scholarsError);

		const missing = emailsOrORCIDs.filter(
			(id) => !scholars.some((scholar) => scholar.email === id || scholar.orcid === id)
		);
		if (missing.length > 0) return this.error('InviteToRoleMissing', null, missing.join(', '));

		const ids: string[] = [];
		const notified: Notification[] = [];
		for (const scholar of scholars) {
			const { data, error } = await this.createVolunteer(
				inviter,
				scholar.id,
				role.id,
				false,
				false,
				null
			);
			if (error) return { error };
			if (data) {
				ids.push(data);
				const inviteResult = await this.emailScholars([scholar.id], 'RoleInvite', [
					role.name,
					venuePath(venue),
					venue.title,
					scholar.id
				]);
				if (inviteResult.notified) notified.push(...inviteResult.notified);
			}
		}
		return { data: ids, notified };
	}

	async acceptRoleInvite(scholar: ScholarID, id: VolunteerID, response: Response) {
		// Updating the volunteer response and, when accepting a first role at
		// the role's venue, settling the welcome grant happen atomically inside
		// the accept_role_invite RPC.
		const { data, error } = await this.client.rpc('accept_role_invite', {
			_volunteer_id: id,
			_response: response
		});
		if (error) return this.error('AcceptRoleInvite', error);

		// Accepting used to be silent, which left a scholar who had just earned
		// welcome tokens with no indication anything had happened.
		const granted = numberField(data, 'welcome_granted') ?? 0;
		const message =
			response !== 'accepted'
				? this.locale.notification.inviteDeclined
				: granted > 0
					? this.locale.notification.inviteAcceptedWithTokens.replace(
							'{amount}',
							granted.toString()
						)
					: this.locale.notification.inviteAccepted;
		return { data: undefined, notified: [{ message }] };
	}

	async getVolunteersByRoles(roleIDs: RoleID[]): Promise<ReadResult<VolunteerRow[] | null>> {
		return this.rows(
			'LoadVolunteer',
			this.client.from('volunteers').select('*').in('roleid', roleIDs)
		);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Preference levels
	// ─────────────────────────────────────────────────────────────────────────

	async createPreferenceLevel(venue: VenueID, label: string): Promise<Result<PreferenceLevelRow>> {
		// New levels go at the end of the current rank order.
		const { data: existing, error: existingError } = await this.client
			.from('preference_levels')
			.select('rank')
			.eq('venueid', venue)
			.order('rank', { ascending: false })
			.limit(1);
		if (existingError) return this.error('CreatePreferenceLevel', existingError);
		const rank = existing.length === 0 ? 0 : existing[0].rank + 1;

		const { data, error } = await this.client
			.from('preference_levels')
			.insert({ venueid: venue, label, rank })
			.select()
			.single();
		if (error) return this.error('CreatePreferenceLevel', error);
		return { data };
	}

	async editPreferenceLevelLabel(id: PreferenceLevelID, label: string): Promise<Result> {
		return this.updatePreferenceLevel(id, { label }, 'EditPreferenceLevel');
	}

	async reorderPreferenceLevel(
		level: PreferenceLevelRow,
		levels: PreferenceLevelRow[],
		direction: -1 | 1
	): Promise<Result> {
		// Find the neighbor we're swapping with by sorted-rank position.
		const sorted = [...levels].sort((a, b) => a.rank - b.rank);
		const index = sorted.findIndex((l) => l.id === level.id);
		const neighborIndex = index + direction;
		if (index < 0 || neighborIndex < 0 || neighborIndex >= sorted.length) return {};
		const neighbor = sorted[neighborIndex];

		// Two-step swap through a sentinel rank to avoid violating the
		// (venueid, rank) unique constraint mid-update.
		const sentinel = Math.max(...sorted.map((l) => l.rank)) + 1;
		const { error: e1 } = await this.client
			.from('preference_levels')
			.update({ rank: sentinel })
			.eq('id', level.id);
		if (e1) return this.error('ReorderPreferenceLevel', e1);
		const { error: e2 } = await this.client
			.from('preference_levels')
			.update({ rank: level.rank })
			.eq('id', neighbor.id);
		if (e2) return this.error('ReorderPreferenceLevel', e2);
		const { error: e3 } = await this.client
			.from('preference_levels')
			.update({ rank: neighbor.rank })
			.eq('id', level.id);
		if (e3) return this.error('ReorderPreferenceLevel', e3);
		return {};
	}

	async deletePreferenceLevel(id: PreferenceLevelID): Promise<Result> {
		const { error } = await this.client.from('preference_levels').delete().eq('id', id);
		return this.errorOrEmpty('DeletePreferenceLevel', error);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Assignments
	// ─────────────────────────────────────────────────────────────────────────

	async createAssignment(
		submission: SubmissionID,
		scholar: ScholarID,
		roleid: RoleID,
		bid: boolean,
		approved: boolean = false,
		preferenceid: PreferenceLevelID | null = null
	): Promise<Result> {
		const { data: role, error: roleError } = await this.client
			.from('roles')
			.select()
			.eq('id', roleid)
			.single();
		if (role === null) {
			console.error(roleError);
			return this.error('CreateAssignment', roleError);
		}

		const { error } = await this.client.from('assignments').insert({
			submission,
			scholar,
			role: roleid,
			bid,
			venue: role.venueid,
			approved,
			preferenceid
		});
		return this.errorOrEmpty('CreateAssignment', error);
	}

	async approveAssignment(
		assignment: AssignmentRow,
		approved: boolean,
		role: RoleRow,
		approver: ScholarID
	): Promise<Result> {
		const { error: assignmentError } = await this.client
			.from('assignments')
			.update({ approved })
			.eq('id', assignment.id);

		if (assignmentError) return this.error('ApproveAssignment', assignmentError);

		// Notify the assigned
		let notified: Notification[] | undefined;
		const scholar = await this.getScholar(approver);
		if (scholar) {
			const emailResult = await this.emailScholars(
				[assignment.scholar],
				approved ? 'AssignmentApproved' : 'AssignmentRemoved',
				[
					scholar.getName() ?? '',
					scholar.getEmail() ?? '',
					role.name,
					await this.venuePathOf(assignment.venue),
					assignment.submission
				]
			);
			notified = emailResult.notified;
		}

		return { data: undefined, notified };
	}

	async updateAssignmentPreference(
		id: AssignmentID,
		preferenceid: PreferenceLevelID | null
	): Promise<Result> {
		const { error } = await this.client.from('assignments').update({ preferenceid }).eq('id', id);
		return this.errorOrEmpty('UpdateAssignmentPreference', error);
	}

	async completeAssignment(assignment: AssignmentID, _completer: ScholarID): Promise<Result> {
		// Authorization, fund-check, token transfer, transaction insert, and
		// assignment update are all atomic inside the complete_assignment RPC.
		// The application layer only dispatches notifications based on the
		// outcome.
		const { data, error } = await this.client.rpc('complete_assignment', {
			_assignment_id: assignment,
			_payment_purpose_template: this.locale.view.transactions.purposeTemplate.compensation,
			_mint_purpose_template: this.locale.view.transactions.purposeTemplate.mint
		});
		if (error) return this.error('CompleteAssignmentRPC', error);

		// Supabase types JSONB-returning RPCs as `Json`, so we narrow at the
		// boundary with runtime-checked type predicates. That gives us a
		// typed `data` without a TypeScript cast (no `as` keyword), and it
		// would actually catch an RPC contract drift at runtime — unlike
		// `as`, which trusts the call blindly.
		if (!isCompleteAssignmentResult(data)) return this.error('CompleteAssignmentRPC');

		if (data.status === 'insufficient') {
			// The RPC already recorded a proposed mint transaction sized at
			// the shortfall. Email the venue's minter(s) so they know to
			// approve it.
			const { data: currency } = await this.client
				.from('currencies')
				.select('minters')
				.eq('id', data.currency_id)
				.single();
			if (currency !== null && currency.minters.length > 0) {
				await this.emailScholars(currency.minters, 'VenueOutOfTokens', [
					data.amount.toString(),
					data.role_name,
					data.shortfall.toString(),
					await this.venuePathOf(data.venue_id),
					data.venue_title
				]);
			}
			return this.error('CompleteAssignmentInsufficientTokens');
		}

		// Tokens have moved. Tell the scholar.
		return this.emailScholars([data.scholar_id], 'WorkCompensated', [
			data.role_name,
			data.amount.toString(),
			await this.venuePathOf(data.venue_id),
			data.submission_id
		]);
	}

	async deleteAssignment(assignment: AssignmentID): Promise<Result> {
		const { error } = await this.client.from('assignments').delete().eq('id', assignment);
		return this.errorOrEmpty('DeleteAssignment', error);
	}

	async getSubmissionAssignments(
		submission: SubmissionID
	): Promise<ReadResult<AssignmentRow[] | null>> {
		return this.rows(
			'LoadAssignment',
			this.client.from('assignments').select('*').eq('submission', submission)
		);
	}

	async getActiveAssignmentsForScholars(
		scholarIDs: ScholarID[]
	): Promise<ReadResult<Pick<AssignmentRow, 'scholar' | 'venue'>[] | null>> {
		return this.rows(
			'LoadAssignment',
			this.client
				.from('assignments')
				.select('scholar, venue')
				.in('scholar', scholarIDs)
				.eq('approved', true)
				.eq('completed', false)
		);
	}

	async getAssignmentsForApproval(
		roleIDs: RoleID[]
	): Promise<ReadResult<AssignmentForApproval[] | null>> {
		return this.rows('LoadAssignment', assignmentsForApprovalQuery(this.client, roleIDs));
	}

	async getAssignmentsAwaitingCompensation(
		roleIDs: RoleID[]
	): Promise<ReadResult<AssignmentAwaitingCompensation[] | null>> {
		return this.rows('LoadAssignment', assignmentsAwaitingCompensationQuery(this.client, roleIDs));
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Transactions
	// ─────────────────────────────────────────────────────────────────────────

	async createTransaction(
		creator: ScholarID,
		fromScholar: ScholarID | null,
		fromVenue: VenueID | null,
		toScholar: ScholarID | null,
		toVenue: VenueID | null,
		tokens: TokenID[],
		currency: CurrencyID,
		purpose: string,
		status: TransactionStatus
	): Promise<Result<TransactionID>> {
		if (toScholar === null && toVenue === null) return this.error('TransactionMissingTo');

		const { data, error } = await this.client
			.from('transactions')
			.insert({
				creator,
				from_scholar: fromScholar,
				from_venue: fromVenue,
				to_scholar: toScholar,
				to_venue: toVenue,
				tokens,
				currency,
				purpose,
				status
			})
			.select()
			.single();

		return error ? this.error('CreateTransaction', error) : { data: data.id };
	}

	async transferTokens(
		creator: ScholarID,
		currency: CurrencyID,
		from: VenueID | ScholarID | string,
		fromKind: 'venueid' | 'scholarid' | 'emailorcid',
		to: VenueID | ScholarID,
		toKind: 'venueid' | 'scholarid' | 'emailorcid',
		amount: number,
		purpose: string,
		transaction: TransactionID | undefined
	): Promise<Result<{ transaction: TransactionID; tokens: TokenID[] }>> {
		// Resolve the from/to entity ids (reads). The atomic token movement and
		// the transaction create/finalize then happen in a single statement
		// inside the transfer_tokens RPC, so a connectivity loss can no longer
		// leave a partial transfer (some tokens moved, no transaction recorded).
		const fromEntity = await this.resolveEntityID(fromKind, from);
		const toEntity = await this.resolveEntityID(toKind, to);

		if (fromEntity === null) return this.error('ScholarNotFound');
		if (toEntity === null) return this.error('ScholarNotFound');

		const { data, error } = await this.client.rpc('transfer_tokens', {
			_currency: currency,
			_from: fromEntity,
			_from_kind: fromKind === 'venueid' ? 'venueid' : 'scholarid',
			_to: toEntity,
			_to_kind: toKind === 'venueid' ? 'venueid' : 'scholarid',
			_amount: amount,
			_purpose: purpose,
			// Null when recording a brand-new transfer; typed non-null by the generator.
			_transaction: (transaction ?? null) as string
		});
		if (error)
			return this.error(
				rpcErrorKey(error, 'TransferVenueTokens', { RR003: 'TransferTokensInsufficient' }),
				error
			);

		const transactionID = stringField(data, 'transaction_id');
		const tokenIDs = stringArrayField(data, 'token_ids');
		if (transactionID === null || tokenIDs === null) return this.error('TransferVenueTokens');
		return { data: { transaction: transactionID, tokens: tokenIDs } };
	}

	async approveTransaction(creator: ScholarID, id: TransactionID) {
		// Authorization (giver / minter, no self-enrichment), any required token
		// minting, the token movement, and the status flip all happen atomically
		// inside the approve_transaction RPC. Previously these were several
		// separate client writes that a connectivity loss could split, moving
		// tokens without finalizing the transaction (or vice versa).
		const { error } = await this.client.rpc('approve_transaction', { _transaction_id: id });
		if (error)
			return this.error(
				rpcErrorKey(error, 'ApproveTransaction', {
					RR001: 'AlreadyApproved',
					RR002: 'SelfDealingApproval',
					RR003: 'TransferTokensInsufficient'
				}),
				error
			);
		return { error: undefined, data: undefined };
	}

	async declineTransaction(
		decliner: ScholarID,
		id: TransactionID,
		reason: string
	): Promise<Result> {
		// Read the transaction first so we know the proposer, original purpose,
		// venue and currency before we update.
		const { data: transaction, error: readError } = await this.client
			.from('transactions')
			.select('creator, purpose, currency, from_venue, to_venue, amount')
			.eq('id', id)
			.single();
		if (readError || !transaction) return this.error('TransactionNotDeclined', readError);

		// Apply the decline — purpose stays untouched, audit columns capture
		// who declined and why.
		//
		// The `status` predicate is what makes this safe against a concurrent
		// approval. Without it the update matched on `id` alone, so an approval
		// landing between the read above and this write would be overwritten: the
		// tokens had already moved and been recorded in token_events, while the
		// transaction ended up saying `declined`. The database now refuses that
		// outright (RR005, see 20260808030000), and matching on status as well turns
		// what would be a raw error into a clean zero-row result we can report.
		const { data: declined, error: updateError } = await this.client
			.from('transactions')
			.update({ status: 'declined', decliner, decline_reason: reason })
			.eq('id', id)
			.eq('status', 'proposed')
			.select('id');
		if (updateError)
			return this.error(
				rpcErrorKey(updateError, 'TransactionNotDeclined', { RR005: 'AlreadyApproved' }),
				updateError
			);
		// Zero rows means someone decided it first — the realistic case being an
		// approval that won the race.
		if (!declined || declined.length === 0) return this.error('AlreadyApproved');

		// Don't email proposers who declined their own transaction.
		if (transaction.creator === decliner) return { error: undefined, data: undefined };

		// Resolve the decliner and currency names + optional venue title for the
		// email body. A transaction always has a from/to side; venue title is
		// only included if either side is a venue.
		const venueID = transaction.from_venue ?? transaction.to_venue;
		const [declinerRow, currencyRow, venueRow] = await Promise.all([
			this.client.from('scholars').select('name, email').eq('id', decliner).single(),
			this.client.from('currencies').select('name').eq('id', transaction.currency).single(),
			venueID
				? this.client.from('venues').select('id, title, slug').eq('id', venueID).single()
				: Promise.resolve({ data: null, error: null })
		]);

		const declinerName = declinerRow.data?.name ?? '';
		const declinerEmail = declinerRow.data?.email ?? '';
		const currencyName = currencyRow.data?.name ?? '';
		const venueTitle = venueRow.data?.title ?? '';
		const amount = transaction.amount.toString();
		// Point back at whichever environment the decline happened in. This runs
		// in the browser, so the page's own origin is the right answer and is
		// already to hand; the templates' other links are resolved server-side
		// from the site_url vault secret.
		const origin =
			typeof window !== 'undefined' ? window.location.origin : 'https://reciprocal.reviews';
		const link =
			venueID && venueRow.data !== null
				? `${origin}/venue/${venuePath(venueRow.data)}/transactions`
				: `${origin}/scholar/${transaction.creator}/transactions`;

		// Pick the template variant: with vs without a venue title slot.
		const args = venueID
			? [
					transaction.purpose,
					amount,
					currencyName,
					venueTitle,
					declinerName,
					declinerEmail,
					reason,
					link
				]
			: [transaction.purpose, amount, currencyName, declinerName, declinerEmail, reason, link];

		await this.emailScholars(
			[transaction.creator],
			venueID ? 'TransactionDeclinedVenue' : 'TransactionDeclined',
			args
		);

		return { error: undefined, data: undefined };
	}

	// The three paginated transaction lists all sort by created_at and then by
	// seq. The tiebreaker is not optional: created_at defaults to now(), which is
	// transaction START time, so every row a single RPC writes carries an
	// identical timestamp — create_submission inserts one charge per author that
	// way. Sorting on created_at alone leaves those rows in an order the planner
	// may choose differently per query, and a LIMIT/OFFSET over an unstable sort
	// can return one row on two pages while skipping another entirely.
	async getScholarTransactions(scholar: ScholarID, page: number = 0) {
		return await transactionListQuery(this.client, page === 0)
			.or(`from_scholar.eq.${scholar},to_scholar.eq.${scholar}`)
			.order('created_at', { ascending: false })
			.order('seq', { ascending: false })
			.range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);
	}

	async getVenueTransactions(venue: VenueID, page: number = 0) {
		return await transactionListQuery(this.client, page === 0)
			.or(`from_venue.eq.${venue},to_venue.eq.${venue}`)
			.order('created_at', { ascending: false })
			.order('seq', { ascending: false })
			.range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);
	}

	async getCurrencyTransactions(currency: CurrencyID, page: number = 0) {
		return await transactionListQuery(this.client, page === 0)
			.eq('currency', currency)
			.order('created_at', { ascending: false })
			.order('seq', { ascending: false })
			.range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);
	}

	async getScholarTransactionCount(scholar: ScholarID): Promise<ReadResult<number | null>> {
		return this.count(
			'LoadTransaction',
			this.client
				.from('transactions')
				.select('*', { count: 'exact', head: true })
				.or(`from_scholar.eq.${scholar},to_scholar.eq.${scholar}`)
		);
	}

	async getVenueTransactionCount(venue: VenueID): Promise<ReadResult<number | null>> {
		return this.count(
			'LoadTransaction',
			this.client
				.from('transactions')
				.select('*', { count: 'exact', head: true })
				.or(`from_venue.eq.${venue},to_venue.eq.${venue}`)
		);
	}

	async getTransactionsByIDs(ids: TransactionID[]): Promise<ReadResult<TransactionRow[] | null>> {
		return this.rows('LoadTransaction', this.client.from('transactions').select('*').in('id', ids));
	}

	async getSubmissionTransactionIDs(
		ids: TransactionID[]
	): Promise<ReadResult<Pick<TransactionRow, 'id'>[] | null>> {
		return this.rows(
			'LoadTransaction',
			this.client.from('transactions').select('id').in('id', ids)
		);
	}

	async getPendingTransactionsByCurrencies(
		currencyIDs: CurrencyID[]
	): Promise<ReadResult<TransactionRow[] | null>> {
		return this.rows(
			'LoadTransaction',
			this.client
				.from('transactions')
				.select('*')
				.eq('status', 'proposed')
				.in('currency', currencyIDs)
		);
	}

	async getOutgoingPendingTransactions(
		scholar: ScholarID
	): Promise<ReadResult<TransactionRow[] | null>> {
		return this.rows(
			'LoadTransaction',
			this.client
				.from('transactions')
				.select('*')
				.eq('status', 'proposed')
				.eq('from_scholar', scholar)
		);
	}

	async getTransactionVenues(
		transactions: Pick<TransactionRow, 'from_venue' | 'to_venue'>[]
	): Promise<ReadResult<VenueRow[] | null>> {
		return this.rows(
			'LoadVenue',
			this.client
				.from('venues')
				.select('*')
				.in(
					'id',
					Array.from(
						new Set(
							transactions
								.map((tr) => [tr.from_venue, tr.to_venue])
								.flat()
								.filter((venueID) => venueID !== null)
						)
					)
				)
		);
	}

	async getTransactionCurrencies(
		transactions: Pick<TransactionRow, 'currency'>[]
	): Promise<ReadResult<CurrencyRow[] | null>> {
		return this.rows(
			'LoadCurrency',
			this.client
				.from('currencies')
				.select('*')
				.in('id', Array.from(new Set(transactions.map((t) => t.currency))))
		);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Emails & conflicts
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * The path segment a venue's mail should link to: its web address once it has one, its
	 * id until then.
	 *
	 * Resolved here, at queue time, rather than at send time like `{origin}` — the one
	 * exception to that rule. Venue mail is queued and sent by the `emails` table's AFTER
	 * INSERT trigger within seconds of each other, so a rename cannot realistically overtake
	 * a message in flight; and if one ever did, the link still resolves, because the venue
	 * layout accepts an id and the address it was renamed from is simply gone either way.
	 *
	 * A round trip per venue-linked email, which is why callers that already hold the venue
	 * row use `venuePath` directly instead.
	 */
	private async venuePathOf(id: VenueID): Promise<string> {
		const { data } = await this.client.from('venues').select('id, slug').eq('id', id).maybeSingle();
		return data === null ? id : venuePath(data);
	}

	/** Use the resend edge function to use the Resend API to send a message to the current user. */
	/** Email scholars by id. Recipient resolution — including skipping scholars with no
	 * verified contact email, which is what enforces "never notify an unverified
	 * address" (#27) — happens inside the RPC, not here. */
	async emailScholars(scholars: ScholarID[], template: EmailType, args: string[]): Promise<Result> {
		return this.queueEmail(template, args, { scholars });
	}

	/**
	 * Queue a steward notification to the shared steward inbox.
	 *
	 * Separate from `queueEmail` because the recipient is not a scholar: it is the
	 * stewards@ alias, which the RPC supplies itself. The RPC also whitelists the events it
	 * will accept, so this cannot become a general channel into the stewards' mailbox.
	 */
	private async queueStewardEmail(template: EmailType, args: string[]): Promise<Result> {
		const { error } = await this.client.rpc('queue_steward_email', {
			_event: template,
			_args: args
		});
		if (error) return this.error('EmailScholar', error);

		const { subject } = renderEmail(template, args);
		return {
			data: undefined,
			notified: [
				{
					message: this.locale.notification.emailedStewards.replace('{subject}', subject)
				}
			]
		};
	}

	/**
	 * Queue a template email through the `queue_email` RPC.
	 *
	 * Direct INSERT into `emails` is revoked: the table's AFTER INSERT trigger sends
	 * branded mail, so accepting a recipient and body from the client made the pipeline an
	 * open relay. The RPC resolves recipients server-side — scholars by id (skipping any
	 * without a verified contact email) or a proposal's editor addresses — and the body is
	 * rendered at send time from the template registry, so no prose crosses the API.
	 *
	 * We still render locally, but only to label the "emailed X about Y" notification; that
	 * copy is display-only and is never what gets delivered.
	 */
	private async queueEmail(
		template: EmailType,
		args: string[],
		target: { scholars?: ScholarID[]; proposal?: ProposalID }
	): Promise<Result> {
		const { data, error } = await this.client.rpc('queue_email', {
			_event: template,
			_args: args,
			_scholars: target.scholars ?? undefined,
			_proposal: target.proposal ?? undefined
		});
		if (error) return this.error('EmailScholar', error);

		const { subject } = renderEmail(template, args);
		const recipients = Array.isArray(data) ? (data as { name?: string; email: string }[]) : [];
		const notificationTemplate = this.locale.notification.emailed;
		return {
			data: undefined,
			notified: recipients.map((recipient) => ({
				message: notificationTemplate
					.replace('{recipient}', recipient.name?.trim() ? recipient.name : recipient.email)
					.replace('{subject}', subject)
			}))
		};
	}

	async declareConflict(
		scholarid: ScholarID,
		submissionid: SubmissionID,
		reason: string
	): Promise<Result> {
		// Is there a submission that this scholar can view with this manuscript ID?
		const { error } = await this.client
			.from('conflicts')
			.insert({ scholarid, submissionid, reason });
		if (error) return this.error('DeclareConflict', error);

		return { data: undefined };
	}
}
