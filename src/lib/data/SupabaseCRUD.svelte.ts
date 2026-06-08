import type { Database } from '$data/database';
import type { AuthError, PostgrestError, SupabaseClient } from '@supabase/supabase-js';
import type {
	AssignmentID,
	AssignmentRow,
	CompensationRow,
	CurrencyID,
	PreferenceLevelID,
	PreferenceLevelRow,
	ProposalID,
	Response,
	RoleID,
	RoleRow,
	ScholarID,
	ScholarRow,
	SubmissionID,
	SubmissionType,
	SubmissionTypeID,
	SupporterID,
	TokenID,
	TransactionID,
	TransactionStatus,
	VenueID,
	VenueRow,
	VolunteerID
} from '../../data/types';
import { renderEmail, type EmailType } from '../../email/templates';
import type Locale from '../locales/Locale';
import CRUD, {
	NullUUID,
	type BulkImportResult,
	type Charge,
	type ImportedSubmission,
	type MarkSubmissionDoneOutcome,
	type Notification,
	type Result,
	type SubmissionBlocker
} from './CRUD';
import Scholar from './Scholar.svelte';

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
function isCompleteAssignmentResult(value: unknown): value is CompleteAssignmentResult {
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

function isMarkSubmissionDoneResult(value: unknown): value is MarkSubmissionDoneResult {
	if (typeof value !== 'object' || value === null || !('status' in value)) return false;
	return (
		value.status === 'completed' || value.status === 'blocked' || value.status === 'insufficient'
	);
}

/** Read a string field from a jsonb object returned by an RPC, or null if
 * absent or the wrong type. The atomic-CRUD RPCs return jsonb_build_object
 * payloads (see migration 20260608000000_atomic_crud.sql). */
function stringField(value: unknown, key: string): string | null {
	if (typeof value !== 'object' || value === null || !(key in value)) return null;
	const field = (value as Record<string, unknown>)[key];
	return typeof field === 'string' ? field : null;
}

/** Read a string[] field from a jsonb object returned by an RPC, or null if
 * absent or not an array of strings. */
function stringArrayField(value: unknown, key: string): string[] | null {
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
function rpcErrorKey(
	error: PostgrestError | null,
	fallback: keyof Locale['error'],
	map: Record<string, keyof Locale['error']>
): keyof Locale['error'] {
	const code = error?.code;
	return (code !== undefined && map[code]) || fallback;
}

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

	async updateSubmissionExpertise(
		submissionID: SubmissionID,
		expertise: string | null
	): Promise<Result> {
		const { error } = await this.client
			.from('submissions')
			.update({ expertise })
			.eq('id', submissionID);
		return this.errorOrEmpty('UpdateSubmissionExpertise', error);
	}

	async updateSubmissionTitle(submissionID: SubmissionID, title: string): Promise<Result> {
		const { error } = await this.client
			.from('submissions')
			.update({ title })
			.eq('id', submissionID);
		return this.errorOrEmpty('UpdateSubmissionTitle', error);
	}

	async updateSubmissionNote(submissionID: SubmissionID, note: string | null): Promise<Result> {
		const { error } = await this.client.from('submissions').update({ note }).eq('id', submissionID);
		return this.errorOrEmpty('UpdateSubmissionNote', error);
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
					data.venue_id,
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
		for (const payout of data.payouts) {
			const result = await this.emailScholars([payout.scholar_id], 'WorkCompensated', [
				payout.role_name,
				payout.amount.toString(),
				data.venue_id,
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

	async verifyCharges(charges: Charge[]): Promise<Result<true | Charge[] | undefined>> {
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
					payment: scholars.some((s) => s.orcid === charge.scholar) ? charge.payment : undefined
				}))
			};

		const scholarIDs = scholars.map((scholar) => scholar.id);

		// Find all of the tokens owned by the set
		const { data: tokens, error: tokenError } = await this.client
			.from('tokens')
			.select('scholar')
			.in('scholar', scholarIDs);
		if (tokenError) {
			return { error: { message: 'Missing token', details: tokenError } };
		}

		// Sum the tokens possessed by each scholar
		const balances = new Map<string, number>();
		for (const token of tokens) {
			if (token.scholar === null) continue;
			const balance = balances.get(token.scholar) ?? 0;
			balances.set(token.scholar, balance + 1);
		}

		// Compute the deficits
		const deficits = charges.map((charge) => {
			const scholarID = scholars.find((scholar) => scholar.orcid === charge.scholar)?.id;
			const balance = scholarID !== undefined ? (balances.get(scholarID) ?? 0) : 0;
			return {
				scholar: charge.scholar,
				payment:
					balance === undefined || charge.payment === undefined
						? undefined
						: balance - charge.payment
			};
		});

		if (deficits.some((deficit) => deficit.payment === undefined || deficit.payment < 0))
			return { data: deficits };

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
		const chargeError = await this.verifyCharges(charges);
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
			return this.error(rpcErrorKey(error, 'NewSubmission', { RR003: 'TransferTokensInsufficient' }), error);

		const submissionID = stringField(data, 'submission_id');
		if (submissionID === null) return { error: { message: this.locale.error.NewSubmission } };
		return { data: submissionID };
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
			note: s.note
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
		};

		return {
			data: {
				submissionIDs: result.submission_ids ?? [],
				transactionID: result.transaction_id,
				mintAmount: result.mint_amount
			}
		};
	}

	async updateSubmissionType(
		submissionID: SubmissionID,
		submissionTypeID: SubmissionTypeID
	): Promise<Result> {
		const { error } = await this.client
			.from('submissions')
			.update({ submission_type: submissionTypeID })
			.eq('id', submissionID);
		if (error) return this.error('UpdateSubmissionType', error);
		else return {};
	}

	/** Register a reactive scholar state. */
	registerScholar(row: ScholarRow) {
		let scholar = this.scholars.get(row.id);
		if (scholar === undefined) {
			scholar = new Scholar(row);
			this.scholars.set(row.id, scholar);
		}
		return scholar;
	}

	async findScholar(emailOrORCID: string): Promise<Result<string>> {
		const { data: scholar, error } = await this.client
			.from('scholars')
			.select('id')
			.or(`orcid.eq.${emailOrORCID},email.eq.${emailOrORCID}`)
			.single();

		return error || scholar === null ? this.error('ScholarNotFound', error) : { data: scholar.id };
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

	async updateScholarEmail(id: ScholarID, email: string): Promise<Result> {
		const { error } = await this.client.from('scholars').update({ email }).eq('id', id);
		if (error) return this.error('UpdateScholarName', error);
		else {
			const state = this.scholars.get(id);
			if (state) state.setEmail(email);
			return {};
		}
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
		const { data, error: insertError } = await this.client
			.from('proposals')
			.insert({ title, url, editors, census, currency, minters, payment_free: paymentFree })
			.select()
			.single();

		if (insertError || data === null) return this.error('CreateProposal', insertError);

		const proposalid = data.id;

		const { error } = await this.addVenueProposalSupporter(scholarid, proposalid, message);

		if (error) return { error };

		// Find the stewards to notify
		const { data: stewards } = await this.client.from('scholars').select('id').eq('steward', true);

		const notified: Notification[] = [];
		if (stewards) {
			const stewardResult = await this.emailScholars(
				stewards.map((s) => s.id),
				'ProposalCreatedStewards',
				[title, proposalid]
			);
			if (stewardResult.notified) notified.push(...stewardResult.notified);
		}

		// Notify editors
		const editorResult = await this.sendEmail(editors, 'ProposalCreatedEditors', [
			title,
			proposalid
		]);
		if (editorResult.notified) notified.push(...editorResult.notified);

		return { data: proposalid, notified };
	}

	async editVenueProposalTitle(venue: ProposalID, title: string): Promise<Result> {
		const { error } = await this.client.from('proposals').update({ title }).eq('id', venue);
		if (error) return this.error('EditProposalTitle', error);
		else return {};
	}

	async editVenueProposalCensus(venue: ProposalID, census: number): Promise<Result> {
		const { error } = await this.client.from('proposals').update({ census }).eq('id', venue);
		if (error) return this.error('EditProposalCensus', error);
		else return {};
	}

	async editVenueProposalEditors(venue: ProposalID, editors: string[]): Promise<Result> {
		const { error } = await this.client.from('proposals').update({ editors }).eq('id', venue);
		if (error) return this.error('EditProposalEditors', error);
		else return {};
	}

	async editVenueProposalMinters(venue: ProposalID, minters: string[]): Promise<Result> {
		const { error } = await this.client.from('proposals').update({ minters }).eq('id', venue);
		if (error) return this.error('EditProposalMinters', error);
		else return {};
	}

	async editVenueProposalURL(venue: ProposalID, url: string): Promise<Result> {
		const { error } = await this.client.from('proposals').update({ url }).eq('id', venue);
		if (error) return this.error('EditProposalURL', error);
		else return {};
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
		if (error) return this.error('ApproveProposalNoVenue', error);

		const venueID = stringField(data, 'venue_id');
		const editorIDs = stringArrayField(data, 'editor_ids');
		const supporterIDs = stringArrayField(data, 'supporter_ids');
		const title = stringField(data, 'title');
		if (venueID === null || editorIDs === null || supporterIDs === null || title === null)
			return this.error('ApproveProposalNoVenue');

		const scholarsToEmail = [...editorIDs, ...supporterIDs];
		const emailResult = await this.emailScholars(scholarsToEmail, 'VenueApproved', [
			title,
			venueID
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

	async updateCurrencyName(id: CurrencyID, name: string): Promise<Result> {
		const { error } = await this.client.from('currencies').update({ name }).eq('id', id);
		return this.errorOrEmpty('UpdateCurrencyName', error);
	}

	async updateCurrencyDescription(id: CurrencyID, description: string) {
		const { error } = await this.client.from('currencies').update({ description }).eq('id', id);
		return this.errorOrEmpty('UpdateCurrencyDescription', error);
	}

	async editVenueDescription(id: VenueID, description: string) {
		const { error } = await this.client.from('venues').update({ description }).eq('id', id);
		return this.errorOrEmpty('EditVenueDescription', error);
	}

	async editVenueAdmins(id: VenueID, admins: string[]) {
		const { error } = await this.client
			.from('venues')
			.update({ admins: Array.from(new Set(admins)) })
			.eq('id', id);
		return this.errorOrEmpty('EditVenueAdmins', error);
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
		const { error } = await this.client.from('venues').update({ title }).eq('id', id);
		return this.errorOrEmpty('EditVenueTitle', error);
	}

	async editVenueURL(id: VenueID, url: string) {
		const { error } = await this.client.from('venues').update({ url }).eq('id', id);
		return this.errorOrEmpty('EditVenueTitle', error);
	}

	async editVenueInactive(id: VenueID, inactive: string | null) {
		const { error } = await this.client.from('venues').update({ inactive }).eq('id', id);
		return this.errorOrEmpty('EditVenueInactive', error);
	}

	async editVenueAnonymousAssignments(id: VenueID, anonymous_assignments: boolean) {
		const { error } = await this.client
			.from('venues')
			.update({ anonymous_assignments })
			.eq('id', id);
		return this.errorOrEmpty('EditVenueAnonymousAssignments', error);
	}

	async editVenueWelcomeAmount(id: VenueID, amount: number) {
		const { error } = await this.client
			.from('venues')
			.update({ welcome_amount: amount })
			.eq('id', id);
		return this.errorOrEmpty('EditVenueWelcomeAmount', error);
	}

	async editVenuePaymentFree(id: VenueID, paymentFree: boolean) {
		const { error } = await this.client
			.from('venues')
			.update({ payment_free: paymentFree })
			.eq('id', id);
		return this.errorOrEmpty('EditVenuePaymentFree', error);
	}

	async editVenueDoneVisibilityDays(id: VenueID, days: number) {
		const { error } = await this.client
			.from('venues')
			.update({ done_visibility_days: days })
			.eq('id', id);
		return this.errorOrEmpty('EditVenueDoneVisibilityDays', error);
	}

	async editVenueTransactionReminderFrequency(id: VenueID, days: number) {
		const { error } = await this.client
			.from('venues')
			.update({ transaction_reminder_frequency_days: days })
			.eq('id', id);
		return this.errorOrEmpty('EditVenueTransactionReminderFrequency', error);
	}

	async createRole(id: VenueID, name: string, description: string = ''): Promise<Result<RoleRow>> {
		const { data, error } = await this.client
			.from('roles')
			.insert({ venueid: id, invited: true, name, description })
			.select()
			.single();
		if (error) return this.error('CreateRole', error);
		else return { data };
	}

	async editRoleName(id: RoleID, name: string) {
		const { error } = await this.client.from('roles').update({ name }).eq('id', id);
		return this.errorOrEmpty('UpdateRoleName', error);
	}

	async editRoleDescription(id: RoleID, description: string) {
		const { error } = await this.client.from('roles').update({ description }).eq('id', id);
		return this.errorOrEmpty('UpdateRoleDescription', error);
	}

	async editRoleInvited(id: RoleID, on: boolean) {
		const { error } = await this.client.from('roles').update({ invited: on }).eq('id', id);
		return this.errorOrEmpty('UpdateRoleInvited', error);
	}

	async editRoleBidding(id: RoleID, biddable: boolean) {
		const { error } = await this.client.from('roles').update({ biddable }).eq('id', id);
		return this.errorOrEmpty('EditRoleBidding', error);
	}

	async editRoleAnonymousAuthors(id: RoleID, anonymous: boolean): Promise<Result> {
		const { error } = await this.client
			.from('roles')
			.update({ anonymous_authors: anonymous })
			.eq('id', id);
		return this.errorOrEmpty('EditRoleAnonymousAuthors', error);
	}

	async editRoleDesiredAssignments(id: RoleID, desiredAssignments: number) {
		const { error } = await this.client
			.from('roles')
			.update({ desired_assignments: desiredAssignments })
			.eq('id', id);
		return this.errorOrEmpty('EditRoleDesiredAssignments', error);
	}

	async editRoleApprover(id: RoleID, approver: RoleID | null) {
		const { error } = await this.client.from('roles').update({ approver }).eq('id', id);
		return this.errorOrEmpty('EditRoleApprover', error);
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

	async createVolunteer(
		inviter: ScholarID,
		scholarid: ScholarID,
		roleid: RoleID,
		accepted: boolean,
		compensate: boolean,
		papers: number | null
	): Promise<Result<string>> {
		// Creating the volunteer record and, when this is the scholar's first
		// role and compensation is requested, recording the proposed welcome
		// grant both happen atomically inside the create_volunteer RPC, so the
		// volunteer can never exist without its welcome grant (or vice versa).
		const { data, error } = await this.client.rpc('create_volunteer', {
			_scholarid: scholarid,
			_roleid: roleid,
			_accepted: accepted,
			_compensate: compensate,
			// Nullable in Postgres ("unspecified"), but typed non-null by the generator.
			_papers: papers as number
		});
		if (error)
			return this.error(rpcErrorKey(error, 'CreateVolunteer', { RR004: 'AlreadyVolunteered' }), error);

		const volunteerID = stringField(data, 'volunteer_id');
		if (volunteerID === null) return this.error('CreateVolunteer');
		return { data: volunteerID };
	}

	async welcomeVolunteer(
		welcomer: ScholarID,
		scholar: ScholarID,
		roleid: RoleID,
		reason: string
	): Promise<Result> {
		// Get the role and the venue.
		const { data: role, error: roleError } = await this.client
			.from('roles')
			.select()
			.eq('id', roleid)
			.single();
		if (role === null) return this.error('WelcomeVolunteer', roleError);
		const venueid = role.venueid;
		const { data: venue, error: venueError } = await this.client
			.from('venues')
			.select()
			.eq('id', venueid)
			.single();
		if (venue === null) return this.error('WelcomeVolunteer', venueError);

		// Payment-free venues have no tokens, so there is nothing to welcome with.
		if (venue.payment_free) return {};

		const welcome = venue.welcome_amount;

		// Record an approved transaction to log the gift.
		const { data: transaction, error } = await this.createTransaction(
			welcomer,
			null,
			venueid,
			scholar,
			null,
			// Create a list of null UUIDs to represent that they don't exist yet.
			new Array(welcome).fill(NullUUID),
			venue.currency,
			reason,
			'proposed'
		);
		if (error) return this.error('WelcomeVolunteer', error.details);

		return transaction ? {} : this.error('WelcomeVolunteer');
	}

	async updateVolunteerActive(id: VolunteerID, active: boolean): Promise<Result> {
		const { error } = await this.client.from('volunteers').update({ active }).eq('id', id);
		return this.errorOrEmpty('UpdateVolunteerActive', error);
	}

	async updateVolunteerExpertise(id: VolunteerID, expertise: string): Promise<Result> {
		const { error } = await this.client.from('volunteers').update({ expertise }).eq('id', id);
		return this.errorOrEmpty('UpdateVolunteerExpertise', error);
	}

	async updateVolunteerPapers(id: VolunteerID, papers: number | null): Promise<Result> {
		const { error } = await this.client.from('volunteers').update({ papers }).eq('id', id);
		return this.errorOrEmpty('UpdateVolunteerPapers', error);
	}

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
		const { error } = await this.client.from('preference_levels').update({ label }).eq('id', id);
		return this.errorOrEmpty('EditPreferenceLevel', error);
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
					venue.id,
					venue.title,
					scholar.id
				]);
				if (inviteResult.notified) notified.push(...inviteResult.notified);
			}
		}
		return { data: ids, notified };
	}

	async acceptRoleInvite(scholar: ScholarID, id: VolunteerID, response: Response) {
		// Updating the volunteer response and, when accepting a first role,
		// recording the proposed welcome grant happen atomically inside the
		// accept_role_invite RPC.
		const { error } = await this.client.rpc('accept_role_invite', {
			_volunteer_id: id,
			_response: response
		});
		return this.errorOrEmpty('AcceptRoleInvite', error);
	}

	async editCurrencyMinters(id: CurrencyID, minters: string[]): Promise<Result> {
		const { error } = await this.client.from('currencies').update({ minters }).eq('id', id);
		return this.errorOrEmpty('EditCurrencyMinters', error);
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

	async resolveEntityID(
		kind: 'venueid' | 'scholarid' | 'emailorcid',
		id: VenueID | ScholarID | string
	): Promise<VenueID | ScholarID | null> {
		if (kind === 'venueid' || kind === 'scholarid') return id;
		const { data: scholar } = await this.findScholar(id);
		if (scholar === undefined) return null;
		return scholar;
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

	async getScholarTransactions(scholar: ScholarID, page: number = 0) {
		return await this.client
			.from('transactions')
			.select('*', { count: 'exact' })
			.or(`from_scholar.eq.${scholar},to_scholar.eq.${scholar}`)
			.order('created_at', { ascending: false })
			.range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);
	}

	async getVenueTransactions(venue: VenueID, page: number = 0) {
		return await this.client
			.from('transactions')
			.select('*', { count: 'exact' })
			.or(`from_venue.eq.${venue},to_venue.eq.${venue}`)
			.order('created_at', { ascending: false })
			.range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);
	}

	async getCurrencyTransactions(currency: CurrencyID, page: number = 0) {
		return await this.client
			.from('transactions')
			.select('*', { count: 'exact' })
			.eq('currency', currency)
			.order('created_at', { ascending: false })
			.range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);
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
			.select('creator, purpose, currency, from_venue, to_venue, tokens')
			.eq('id', id)
			.single();
		if (readError || !transaction) return this.error('TransactionNotDeclined', readError);

		// Apply the decline — purpose stays untouched, audit columns capture
		// who declined and why.
		const { error: updateError } = await this.client
			.from('transactions')
			.update({ status: 'declined', decliner, decline_reason: reason })
			.eq('id', id);
		if (updateError) return this.errorOrEmpty('TransactionNotDeclined', updateError);

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
				? this.client.from('venues').select('title').eq('id', venueID).single()
				: Promise.resolve({ data: null, error: null })
		]);

		const declinerName = declinerRow.data?.name ?? '';
		const declinerEmail = declinerRow.data?.email ?? '';
		const currencyName = currencyRow.data?.name ?? '';
		const venueTitle = venueRow.data?.title ?? '';
		const amount = transaction.tokens.length.toString();
		const link = venueID
			? `https://reciprocal.reviews/venue/${venueID}/transactions`
			: `https://reciprocal.reviews/scholar/${transaction.creator}/transactions`;

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
					assignment.venue,
					assignment.submission
				]
			);
			notified = emailResult.notified;
		}

		return { data: undefined, notified };
	}

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

	async updateAssignmentPreference(
		id: AssignmentID,
		preferenceid: PreferenceLevelID | null
	): Promise<Result> {
		const { error } = await this.client.from('assignments').update({ preferenceid }).eq('id', id);
		return this.errorOrEmpty('UpdateAssignmentPreference', error);
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

		// Notify whoever can act on this request, not the requester themselves.
		// "Can act on it" matches canApproveAssignment.ts: anyone approved on
		// this submission for the role that approves the requested role, plus
		// venue admins as a fallback when no approver is assigned yet.
		const recipients = new Set<ScholarID>();

		const { data: role, error: roleError } = await this.client
			.from('roles')
			.select('approver')
			.eq('id', roleID)
			.single();
		if (roleError) return this.error('CompensationAssignmentCheck', roleError);

		if (role.approver !== null) {
			const { data: approverAssignments, error: approverError } = await this.client
				.from('assignments')
				.select('scholar')
				.eq('submission', submission.id)
				.eq('role', role.approver)
				.eq('approved', true);
			if (approverError) return this.error('CompensationAssignmentCheck', approverError);
			for (const a of approverAssignments ?? []) recipients.add(a.scholar);
		}

		if (recipients.size === 0) {
			const { data: venue, error: venueError } = await this.client
				.from('venues')
				.select('admins')
				.eq('id', venueID)
				.single();
			if (venueError) return this.error('CompensationAssignmentCheck', venueError);
			for (const admin of venue.admins) recipients.add(admin);
		}

		recipients.delete(scholarID);

		// No one to notify (shouldn't happen given the admins fallback, but
		// don't error if it does — the assignment was still created).
		if (recipients.size === 0) return { data: undefined, error: undefined };

		return this.emailScholars([...recipients], 'CompensationRequested', [
			venueID,
			submission.id,
			note
		]);
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
					data.venue_id,
					data.venue_title
				]);
			}
			return this.error('CompleteAssignmentInsufficientTokens');
		}

		// Tokens have moved. Tell the scholar.
		return this.emailScholars([data.scholar_id], 'WorkCompensated', [
			data.role_name,
			data.amount.toString(),
			data.venue_id,
			data.submission_id
		]);
	}

	async deleteAssignment(assignment: AssignmentID): Promise<Result> {
		const { error } = await this.client.from('assignments').delete().eq('id', assignment);
		return this.errorOrEmpty('DeleteAssignment', error);
	}

	/** Use the resend edge function to use the Resend API to send a message to the current user. */
	async emailScholars(scholars: ScholarID[], template: EmailType, args: string[]): Promise<Result> {
		// Get the email addresses and names of the specified scholars. Names are
		// used to produce per-recipient notification banners.
		let { data: scholarData, error: scholarsError } = await this.client
			.from('scholars')
			.select('id, email, name')
			.in('id', scholars);
		if (scholarData === null) return this.error('EmailScholar', scholarsError);

		// Ignore scholars without an email address.
		const scholarsWithEmail = scholarData.filter(
			(scholar): scholar is { id: string; email: string; name: string } => scholar.email !== null
		);

		return this.sendEmail(scholarsWithEmail, template, args);
	}

	/** Email some people who aren't scholars */
	async sendEmail(
		emails: string[] | { id: ScholarID; email: string; name?: string }[],
		template: EmailType,
		args: string[]
	): Promise<Result> {
		// Make sure all the scholar emails have the shape of an email address.
		const missingEmails = emails.filter(
			(email) => !/^.+@.+$/.test(typeof email === 'string' ? email : email.email)
		);
		if (!emails.every((email) => /^.+@.+$/.test(typeof email === 'string' ? email : email.email)))
			return this.error(
				'EmailScholar',
				null,
				`Invalid email addresses: ${missingEmails.map((email) => email).join(', ')}`
			);

		const { subject, message } = renderEmail(template, args);

		// The scholar whose action is sending these emails, so they can later see
		// what they sent (null when sent without an authenticated user).
		const {
			data: { user }
		} = await this.client.auth.getUser();
		const sender = user?.id ?? null;

		// Insert the emails into the database, which will trigger the edge function to send the email via Resend.
		const { error: emailInsertError } = await this.client.from('emails').insert(
			emails.map((email) => ({
				scholar: typeof email === 'string' ? null : email.id,
				sender,
				email: typeof email === 'string' ? email : email.email,
				event: template,
				venue: null,
				subject: subject,
				message
			}))
		);
		if (emailInsertError) return this.error('EmailScholar', emailInsertError);

		// We rely on an database trigger to call the edge function to send the email after the row is inserted into the emails table.
		// This is slower and less direct, but ensures that the email sending functionality only lives in one place.

		const notificationTemplate = this.locale.notification.emailed;
		return {
			data: undefined,
			notified: emails.map((email) => {
				const recipient =
					typeof email === 'string'
						? email
						: ((email.name?.trim() ? email.name : email.email) ?? email.email);
				return {
					message: notificationTemplate
						.replace('{recipient}', recipient)
						.replace('{subject}', subject)
				};
			})
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
