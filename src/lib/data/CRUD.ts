import {
	type CurrencyID,
	type CurrencyRow,
	type ConflictRow,
	type ProposalID,
	type ProposalRow,
	type RoleID,
	type ScholarID,
	type ScholarRow,
	type SupporterID,
	type VenueID,
	type VolunteerID,
	type VolunteerRow,
	type Response,
	type TokenID,
	type TransactionStatus,
	type TransactionRow,
	type AssignmentID,
	type RoleRow,
	type AssignmentRow,
	type VenueRow,
	type SubmissionID,
	type SubmissionRow,
	type TransactionID,
	type SubmissionTypeID,
	type SubmissionType,
	type CompensationRow,
	type PreferenceLevelID,
	type PreferenceLevelRow,
	type ThanksRow,
	type ThanksID,
	type NotificationSettingRow,
	type ThanksStatus
} from '../../data/types';
import { getContext, setContext } from 'svelte';
import type Scholar from './Scholar.svelte';
import type { AuthError, PostgrestError, PostgrestResponse } from '@supabase/supabase-js';
import type { EmailType, OptionalEmailType } from '../../email/templates';
import type SupabaseCRUD from './SupabaseCRUD.svelte';
import type {
	AssignmentAwaitingCompensation,
	AssignmentForApproval,
	DevScholar,
	CurrencyHolderCounts,
	ProposalSupporter,
	ScholarMatch,
	ScholarReview,
	ScholarVolunteering,
	TokenBalance,
	TransactionListRow,
	VenueCommitment,
	VenueSettingsVolunteer,
	VenueVolunteer
} from './SupabaseCRUD.svelte';

export const DatabaseSymbol = Symbol('database');
export const NullUUID = '00000000-0000-0000-0000-000000000000';

export function getDB(): () => SupabaseCRUD {
	return getContext<() => SupabaseCRUD>(DatabaseSymbol);
}

export function setDB(db: () => SupabaseCRUD) {
	setContext(DatabaseSymbol, db);
}

export type DBError = { message: string; details?: PostgrestError | AuthError };

/** A descriptor of a notification side effect. Carries a pre-localized
 * message so the feedback layer can render it without needing locale
 * access. The CRUD layer (which has locale via this.locale) is responsible
 * for formatting. */
export type Notification = { message: string };

export type Result<Type = undefined> = {
	data?: Type;
	error?: DBError;
	/** Optional notifications produced by the action — emails queued, etc.
	 * The feedback layer renders one banner per entry. */
	notified?: Notification[];
};

/** The result of a read method used by page load functions (#137). Unlike
 * {@link Result}, `data` is always present (it carries the rows, or null when
 * the row is missing or the query failed) so callers can destructure `data`
 * with the same nullability the raw query builder used to give them.
 *
 * Read failures are logged by the implementation AND reported here. Most callers
 * only want `data`, but the two reasons it can be null are not the same answer: a
 * `.maybeSingle()` that finds nothing yields null with no `error`, while a failed
 * query yields null with one. A route that renders "not found" for the first and
 * "something went wrong" for the second needs to tell them apart. */
export type ReadResult<Type> = { data: Type; error?: DBError };

/** What `ensure_scholar` found when asked to repair the caller's own scholar row.
 * `orcid_conflict` is the one that needs a person: another scholar row already holds
 * this account's ORCID iD, so two accounts are claiming one researcher. */
export type EnsureScholarOutcome = 'exists' | 'created' | 'orcid_conflict' | 'no_account';

export type Charge = { scholar: string; payment: number | undefined };

/** Whether one author can cover the charge proposed for them.
 *
 * `covered: undefined` means the scholar could not be resolved at all;
 * `false` means they hold too little. Deliberately a boolean rather than the
 * remaining balance: the form only ever needed to name who cannot pay, and the
 * submitter is not entitled to know how much anybody else holds (#109). */
export type ChargeCoverage = { scholar: string; covered: boolean | undefined };

export type ImportedSubmission = {
	title: string;
	externalID: string;
	previousID: string | null;
	expertise: string | null;
	submission_type: SubmissionTypeID;
	note: string | null;
};

export type BulkImportResult = {
	submissionIDs: SubmissionID[];
	transactionID: TransactionID | null;
	mintAmount: number;
};

/** A non-editor assignment that is approved but not yet completed, returned
 * by markSubmissionDone when the submission can't be completed yet. */
export type SubmissionBlocker = {
	assignment_id: AssignmentID;
	role_id: RoleID;
	role_name: string;
	scholar_id: ScholarID;
};

/** The three branches of the mark_submission_done RPC outcome. */
export type MarkSubmissionDoneOutcome =
	| { status: 'completed'; total_amount: number; recipients: ScholarID[] }
	| { status: 'blocked'; blockers: SubmissionBlocker[] }
	| { status: 'insufficient'; shortfall: number; total_amount: number };

/** This abstract class defines an interface for database access. It's useful for defining mocks as well as enables us to change databases if necessary. */
export default abstract class CRUD {
	/** Insert a new submission in the database and return a list of transaction ids that paid for it. */
	abstract createSubmission(
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
	): Promise<Result<SubmissionID>>;

	/** Atomically insert a batch of free imported submissions and a single proposed
	 * mint transaction sized to the sum of each submission's type cost. The
	 * minter approves the transaction separately to fund reviewer compensation. */
	abstract bulkImportSubmissions(
		venue: VenueID,
		submissions: ImportedSubmission[],
		importNote: string | null
	): Promise<Result<BulkImportResult>>;

	abstract updateSubmissionType(
		submissionID: SubmissionID,
		submissionTypeID: SubmissionTypeID
	): Promise<Result>;

	/** Given a submission ID, update it's data. */
	abstract updateSubmissionExpertise(
		submissionID: SubmissionID,
		expertise: string | null
	): Promise<Result>;

	abstract updateSubmissionTitle(submissionID: SubmissionID, title: string | null): Promise<Result>;

	abstract updateSubmissionNote(submissionID: SubmissionID, note: string | null): Promise<Result>;

	/** Mark a submission as done. Authorized for priority-0 editors only.
	 * Validates that every non-editor approved assignment is already
	 * compensated, then atomically compensates every uncompleted priority-0
	 * editor assignment on the submission and flips the status. Returns
	 * structured information about blockers, insufficient funds, or success
	 * via the notification facility. Reopening is forbidden by design. */
	abstract markSubmissionDone(
		submissionID: SubmissionID
	): Promise<Result<MarkSubmissionDoneOutcome>>;

	/** Check whether the given scholars have enough tokens for the given payments,
	 * denominated in the given currency. True if so, and a per-scholar can/cannot
	 * otherwise. The currency is required: a balance is only meaningful within one,
	 * and counting a scholar's holdings across all of them makes this disagree with
	 * the create_submission RPC that ultimately decides.
	 *
	 * Answers can/cannot rather than by-how-much. Balances are private (#109) and a
	 * submitter is not in the audience for their co-authors' — being named on a
	 * manuscript together confers nothing. The form never displayed the number
	 * anyway; it only ever named who was short. */
	abstract verifyCharges(
		charges: Charge[],
		currency: CurrencyID
	): Promise<Result<true | ChargeCoverage[] | undefined>>;

	abstract registerScholar(scholar: ScholarRow): Scholar;

	abstract findScholar(emailOrORCID: string): Promise<Result<ScholarID | undefined>>;
	/** Of the given email addresses, those that belong to no scholar. Matches on the
	 * verified contact email alone, exactly as approve_venue_proposal does, so what a
	 * proposal form reports and what approval will actually resolve cannot disagree. */
	abstract findUnknownAddresses(addresses: string[]): Promise<ReadResult<string[]>>;
	/** Up to three scholars whose name contains the query, for picking a
	 * co-author whose ORCID the submitter doesn't know. */
	abstract findScholarsByName(query: string): Promise<ReadResult<ScholarMatch[]>>;
	/** Every scholar, for the local-only sign-in list on /login. */
	abstract getScholarsForDevSignIn(): Promise<ReadResult<DevScholar[] | null>>;

	/** Given a scholar ID, get information about the scholar, except the scholar's transactions */
	abstract getScholar(scholarID: ScholarID): Promise<Scholar | null>;

	/** Update scholar's name */
	abstract updateScholarName(id: ScholarID, name: string): Promise<Result>;

	/** Update scholar's availabilty */
	abstract updateScholarAvailability(id: ScholarID, available: boolean): Promise<Result>;

	/** Update scholar's reviewing status. */
	abstract updateScholarStatus(id: ScholarID, status: string): Promise<Result>;

	/** Which optional notices this scholar has silenced. Only their own rows are readable,
	 * so this returns nothing for anyone else's profile — the preference is deliberately
	 * private, unlike the rest of a scholar's metadata. An absent row means the default,
	 * which is on. */
	abstract getNotificationSettings(
		scholar: ScholarID
	): Promise<ReadResult<NotificationSettingRow[] | null>>;

	/** Turn one optional notice on or off for this scholar. Only templates marked
	 * `optional` in the email registry can be silenced; consequential mail — a charge, a
	 * decline, a verification — carries no such flag and has no setting. */
	abstract updateNotificationSetting(
		scholar: ScholarID,
		event: OptionalEmailType,
		enabled: boolean
	): Promise<Result>;

	/** Begin/resend/change contact-email verification for the current scholar (#27).
	 * Records a pending candidate + token and queues a verification link to `email`,
	 * entirely inside the database — the raw token is never returned to the client, and
	 * the caller supplies neither the message body nor the link's origin. Token
	 * consumption happens in the verify route's server load (see
	 * src/routes/[[lang]]/verify/[token]) via the anon-callable verify_email RPC. */
	abstract requestEmailVerification(email: string): Promise<Result>;

	/** Export everything the platform holds about a scholar, as one JSON document.
	 * A scholar may export themselves; a steward may export on their behalf for a
	 * request that arrives out of band. Fulfils the portability half of the terms
	 * (page.terms.paragraph.rights). */
	abstract exportScholarData(scholar: ScholarID): Promise<Result<unknown>>;

	/** Erase a scholar: destroy every field that identifies them, keeping the row
	 * as an anonymous tombstone. Deletion is not possible — fourteen tables
	 * reference scholars(id), including transactions.creator, which is NOT NULL —
	 * and would in any case destroy records belonging to other people. The erasure
	 * is recorded in `erasures` so it can be re-applied after a restore. */
	abstract eraseScholar(scholar: ScholarID): Promise<Result>;

	/** Promote or demote a steward. `steward` is privilege-bearing and no client role
	 * may write it — the UPDATE grant on `scholars` omits the column — so this goes
	 * through the set_steward RPC, which is SECURITY DEFINER and gated on isSteward().
	 * Resolves to `false` when the scholar already had the requested status, which is
	 * reported rather than raised. Nobody may demote themselves, and the last steward
	 * may not be demoted at all: with the RPC as the only path to the column, a
	 * platform with no stewards could never appoint one again. */
	abstract setSteward(scholar: ScholarID, steward: boolean): Promise<Result<boolean>>;

	/** Promote whoever holds this email address or ORCID iD, resolving them first so a
	 * steward can type an address rather than a uuid — the same shape as adding a
	 * currency minter. There is no `removeSteward(emailOrORCID)` twin: demotion
	 * happens from a list that already carries the scholar's id. */
	abstract addSteward(emailOrORCID: string): Promise<Result<ScholarID>>;

	/** Propose a venue */
	abstract proposeVenue(
		scholar: ScholarID,
		venue: string,
		url: string,
		editors: string[],
		currency: CurrencyID | null,
		minters: string[],
		size: number,
		message: string,
		paymentFree?: boolean
	): Promise<Result<ProposalID>>;

	abstract editVenueProposalTitle(venue: ProposalID, title: string): Promise<Result>;
	abstract editVenueProposalCensus(venue: ProposalID, census: number): Promise<Result>;
	abstract editVenueProposalEditors(venue: ProposalID, editors: string[]): Promise<Result>;
	abstract editVenueProposalURL(venue: ProposalID, url: string): Promise<Result>;

	/** Delete a proposal venue */
	abstract deleteVenueProposal(proposal: ProposalID): Promise<Result>;

	/** Approval a venue proposal */
	abstract approveVenueProposal(proposal: ProposalID): Promise<Result<string>>;

	/** Add support for a proposal */
	abstract addVenueProposalSupporter(
		scholar: ScholarID,
		proposal: ProposalID,
		message: string
	): Promise<Result>;

	abstract editVenueProposalSupport(support: SupporterID, message: string): Promise<Result>;
	abstract deleteVenueProposalSupport(support: SupporterID): Promise<Result>;

	abstract updateCurrencyName(id: CurrencyID, name: string): Promise<Result>;
	abstract updateCurrencyDescription(id: CurrencyID, description: string): Promise<Result>;

	abstract editVenueDescription(id: VenueID, description: string): Promise<Result>;
	abstract editVenueAdmins(id: VenueID, admins: string[]): Promise<Result>;
	abstract addVenueAdmin(id: VenueID, emailOrORCID: string): Promise<Result>;
	abstract editVenueTitle(id: VenueID, title: string): Promise<Result>;
	abstract editVenueURL(id: VenueID, url: string): Promise<Result>;
	/** Set or change the venue's web address. Changing one releases the old address
	 * immediately: nothing reserves it, nothing redirects from it, and every link that
	 * used it breaks. The interface warns before doing it. */
	abstract editVenueSlug(id: VenueID, slug: string): Promise<Result>;
	abstract editVenueInactive(id: VenueID, inactive: string | null): Promise<Result>;
	abstract editVenueAnonymousAssignments(id: VenueID, anonymous: boolean): Promise<Result>;
	/** Toggle whether author thank-you notes to reviewers require vetting. */
	abstract editVenueVetThanks(id: VenueID, vet: boolean): Promise<Result>;
	abstract editVenueWelcomeAmount(id: VenueID, amount: number): Promise<Result>;
	abstract editVenuePaymentFree(id: VenueID, paymentFree: boolean): Promise<Result>;
	abstract editVenueDoneVisibilityDays(id: VenueID, days: number): Promise<Result>;
	abstract editVenueTransactionReminderFrequency(id: VenueID, days: number): Promise<Result>;

	abstract createRole(id: VenueID, name: string): Promise<Result<RoleRow>>;
	abstract editRoleName(id: RoleID, name: string): Promise<Result>;
	abstract editRoleDescription(id: RoleID, description: string): Promise<Result>;
	abstract editRoleInvited(id: RoleID, on: boolean): Promise<Result>;
	abstract editRoleBidding(id: RoleID, bidding: boolean): Promise<Result>;
	abstract editRoleAnonymousAuthors(id: RoleID, anonymous: boolean): Promise<Result>;
	abstract editRoleApprover(id: RoleID, approver: RoleID | null): Promise<Result>;
	abstract editRoleDesiredAssignments(id: RoleID, bidLimit: number | null): Promise<Result>;
	abstract reorderRole(role: RoleRow, roles: RoleRow[], direction: -1 | 1): Promise<Result>;
	abstract deleteRole(id: RoleID): Promise<Result>;

	abstract createSubmissionType(
		venue: VenueID,
		name: string,
		description: string,
		revision: SubmissionTypeID | null,
		cost?: number
	): Promise<Result<SubmissionType>>;

	abstract editSubmissionType(
		id: SubmissionTypeID,
		name: string,
		description: string,
		revision: SubmissionTypeID | null
	): Promise<Result>;

	/** Set the cost, in the venue's currency, to submit a manuscript of this type. */
	abstract editSubmissionTypeCost(id: SubmissionTypeID, cost: number): Promise<Result>;

	abstract deleteSubmissionType(id: SubmissionTypeID): Promise<Result>;

	abstract createCompensation(
		submission_type: SubmissionTypeID,
		role: RoleID,
		amount: number | null,
		rationale: string
	): Promise<Result<CompensationRow>>;

	abstract editCompensation(
		submission_type: SubmissionTypeID,
		role: RoleID,
		amount: number | null,
		rationale: string
	): Promise<Result>;

	abstract createVolunteer(
		inviter: ScholarID,
		scholarid: ScholarID,
		roleid: RoleID,
		accepted: boolean,
		compensate: boolean,
		papers: number | null
	): Promise<Result<string>>;

	abstract updateVolunteerActive(id: VolunteerID, active: boolean): Promise<Result>;
	abstract updateVolunteerExpertise(id: VolunteerID, expertise: string): Promise<Result>;
	abstract updateVolunteerPapers(id: VolunteerID, papers: number | null): Promise<Result>;

	/** Create a new preference level for a venue. New levels are appended after the
	 * highest current rank. */
	abstract createPreferenceLevel(
		venue: VenueID,
		label: string
	): Promise<Result<PreferenceLevelRow>>;
	abstract editPreferenceLevelLabel(id: PreferenceLevelID, label: string): Promise<Result>;
	/** Swap the ranks of the level and its neighbor in the given direction. */
	abstract reorderPreferenceLevel(
		level: PreferenceLevelRow,
		levels: PreferenceLevelRow[],
		direction: -1 | 1
	): Promise<Result>;
	abstract deletePreferenceLevel(id: PreferenceLevelID): Promise<Result>;
	abstract inviteToRole(
		inviter: ScholarID,
		role: RoleRow,
		venue: VenueRow,
		emails: string[]
	): Promise<Result<string[]>>;

	abstract acceptRoleInvite(
		scholar: ScholarID,
		id: VolunteerID,
		response: Response
	): Promise<Result>;

	abstract editCurrencyMinters(id: CurrencyID, minters: string[]): Promise<Result>;
	abstract addCurrencyMinter(
		id: CurrencyID,
		minters: string[],
		emailOrORCID: string
	): Promise<Result>;

	abstract mintTokens(
		creator: ScholarID,
		id: CurrencyID,
		amount: number,
		to: VenueID,
		purpose: string
	): Promise<Result<TokenID[]>>;

	/** Move N tokens from source to destination, returning a transaction ID. */
	abstract transferTokens(
		scholar: ScholarID,
		currency: CurrencyID,
		from: VenueID,
		fromKind: 'venueid' | 'scholarid' | 'emailorcid',
		to: string,
		toKind: 'venueid' | 'scholarid' | 'emailorcid',
		amount: number,
		purpose: string,
		/* If there's an existing proposed transaction, the ID for it. Otherwise, a transaction is created. */
		transaction: TransactionID | undefined
	): Promise<Result<{ transaction: TransactionID; tokens: TokenID[] }>>;

	/** Insert a new transaction in the database */
	abstract createTransaction(
		creator: ScholarID,
		fromScholar: ScholarID | null,
		fromVenue: VenueID | null,
		toScholar: ScholarID | null,
		toVenue: VenueID | null,
		tokens: TokenID[],
		currency: CurrencyID,
		purpose: string,
		status: TransactionStatus
	): Promise<Result<string>>;

	/**
	 * Given a transaction ID that is pending, transfers tokens based on the transaction.
	 * */
	abstract approveTransaction(creator: ScholarID, id: TransactionID): Promise<Result<undefined>>;

	/** Mark the transaction declined. The original `purpose` is preserved;
	 * `decliner` records the scholar who declined and `decline_reason`
	 * captures their explanation. If `decliner` differs from the transaction's
	 * `creator`, emails the creator with the reason and decliner identity. */
	abstract declineTransaction(
		decliner: ScholarID,
		id: TransactionID,
		reason: string
	): Promise<Result>;

	/** Update an assignment for a submission */
	abstract approveAssignment(
		assignment: AssignmentRow,
		approved: boolean,
		role: RoleRow,
		approver: ScholarID
	): Promise<Result>;

	/** Create a new assignment record. `preferenceid` is meaningful only on bids
	 * and only when the venue has defined preference levels. */
	abstract createAssignment(
		submission: SubmissionID,
		scholar: ScholarID,
		role: RoleID,
		bid: boolean,
		approved?: boolean,
		preferenceid?: PreferenceLevelID | null
	): Promise<Result>;

	/** Update the bidder's preference level on an existing bid assignment. */
	abstract updateAssignmentPreference(
		id: AssignmentID,
		preferenceid: PreferenceLevelID | null
	): Promise<Result>;

	/** Request compensation for a manuscript the scholar has volunteered for */
	abstract requestCompensation(
		scholar: ScholarID,
		venue: VenueID,
		manuscript: string,
		role: RoleID,
		note: string
	): Promise<Result>;

	/** Create a new assignment record */
	abstract completeAssignment(id: AssignmentID, completer: ScholarID): Promise<Result>;

	abstract deleteAssignment(assignment: AssignmentID): Promise<Result>;

	/** Queue a template email to the given scholars. Recipients are resolved server-side
	 * from these ids; scholars with no verified contact email are skipped (#27). There is
	 * deliberately no way to email an arbitrary address, and no way to supply a body —
	 * both would make the branded pipeline an open relay. */
	abstract emailScholars(scholars: ScholarID[], event: EmailType, args: string[]): Promise<Result>;

	/** Add a conflict */
	abstract declareConflict(
		scholar: ScholarID,
		submission: SubmissionID,
		reason: string
	): Promise<Result>;

	// --- Read methods for page load functions (#137) ---
	// Load functions read through these so the raw query builder never escapes
	// the data layer. Each resolves with `data` (null on error or missing single
	// rows); failures are logged by the implementation rather than surfaced.

	/** Paginated transactions a scholar is the source or destination of. */
	abstract getScholarTransactions(
		scholar: ScholarID,
		page?: number
	): Promise<PostgrestResponse<TransactionListRow>>;
	/** Paginated transactions a venue is the source or destination of. */
	abstract getVenueTransactions(
		venue: VenueID,
		page?: number
	): Promise<PostgrestResponse<TransactionListRow>>;
	/** Paginated transactions in a currency. */
	abstract getCurrencyTransactions(
		currency: CurrencyID,
		page?: number
	): Promise<PostgrestResponse<TransactionListRow>>;

	abstract getScholarRow(id: ScholarID): Promise<ReadResult<ScholarRow | null>>;
	/** Create the signed-in scholar's row if it is somehow missing, and report what
	 * happened. A scholar row is created once, by a trigger, when the account is
	 * created; if that does not happen the account is unusable and cannot recover on
	 * its own, because signing in again does not re-create the auth user. Called from
	 * the root layout when there is a session but no scholar. */
	abstract ensureScholar(): Promise<Result<EnsureScholarOutcome>>;
	abstract getScholarsByIDs(ids: ScholarID[]): Promise<ReadResult<ScholarRow[] | null>>;
	abstract getScholarNames(
		ids: ScholarID[]
	): Promise<ReadResult<Pick<ScholarRow, 'id' | 'name'>[] | null>>;
	abstract getStewards(): Promise<ReadResult<Pick<ScholarRow, 'id' | 'name'>[] | null>>;

	abstract getVenue(id: VenueID): Promise<ReadResult<VenueRow | null>>;
	/** Resolve a venue from a URL path segment, which is its web address once it has one
	 * and its id until then. Both forms keep working, so mail already sent still lands. */
	abstract getVenueByPath(path: string): Promise<ReadResult<VenueRow | null>>;
	/** Whether no venue holds this web address yet. Advisory only — two venues can pass
	 * this check at the same moment, and the unique index is what settles it. */
	abstract isVenueAddressAvailable(slug: string): Promise<ReadResult<boolean>>;
	abstract getVenues(): Promise<ReadResult<VenueRow[] | null>>;
	abstract getVenuesByIDs(ids: VenueID[]): Promise<ReadResult<VenueRow[] | null>>;
	abstract getCurrencyVenues(currency: CurrencyID): Promise<ReadResult<VenueRow[] | null>>;
	abstract getScholarAdminVenues(
		scholar: ScholarID
	): Promise<ReadResult<Pick<VenueRow, 'id' | 'title' | 'slug'>[] | null>>;

	abstract getCurrency(id: CurrencyID): Promise<ReadResult<CurrencyRow | null>>;
	abstract getCurrencies(): Promise<ReadResult<CurrencyRow[] | null>>;
	abstract getCurrenciesByIDs(ids: CurrencyID[]): Promise<ReadResult<CurrencyRow[] | null>>;
	abstract getScholarMintingCurrencies(
		scholar: ScholarID
	): Promise<ReadResult<CurrencyRow[] | null>>;

	abstract getVenueRoles(venue: VenueID): Promise<ReadResult<RoleRow[] | null>>;
	abstract getRolesByApprover(roleIDs: RoleID[]): Promise<ReadResult<RoleRow[] | null>>;

	// Balances are count(*) over `tokens`, one row per token, so these are all
	// counts rather than reads. Fetching the rows and taking `.length` in the
	// browser — which is what these used to do — is wrong rather than merely slow:
	// PostgREST caps a response at `max_rows` and truncation is not an error, so
	// every such balance silently stopped at 1000.
	/** How many tokens of the given currency the venue's reserve holds. */
	abstract getVenueTokenCount(
		venue: VenueID,
		currency: CurrencyID
	): Promise<ReadResult<number | null>>;
	/** A currency's total supply, and how many scholars and venues hold any of it. */
	abstract getCurrencyHolderCounts(
		currency: CurrencyID
	): Promise<ReadResult<CurrencyHolderCounts | null>>;
	/** How many tokens the scholar holds, keyed by currency id. */
	abstract getScholarBalances(scholar: ScholarID): Promise<ReadResult<Record<string, number>>>;
	/** The scholar's total token count across every currency, for the header balance. */
	abstract getScholarTokenCount(scholar: ScholarID): Promise<ReadResult<number>>;
	/** How many tokens of one currency each named scholar holds. Scholars holding
	 * none are absent rather than zero. */
	abstract getTokenBalances(
		currency: CurrencyID,
		scholarIDs: ScholarID[]
	): Promise<ReadResult<TokenBalance[] | null>>;

	abstract getVenueTransactionCount(venue: VenueID): Promise<ReadResult<number | null>>;
	abstract getScholarTransactionCount(scholar: ScholarID): Promise<ReadResult<number | null>>;
	abstract getTransactionsByIDs(ids: TransactionID[]): Promise<ReadResult<TransactionRow[] | null>>;
	abstract getSubmissionTransactionIDs(
		ids: TransactionID[]
	): Promise<ReadResult<Pick<TransactionRow, 'id'>[] | null>>;
	abstract getPendingTransactionsByCurrencies(
		currencyIDs: CurrencyID[]
	): Promise<ReadResult<TransactionRow[] | null>>;
	abstract getOutgoingPendingTransactions(
		scholar: ScholarID
	): Promise<ReadResult<TransactionRow[] | null>>;
	abstract getTransactionVenues(
		transactions: Pick<TransactionRow, 'from_venue' | 'to_venue'>[]
	): Promise<ReadResult<VenueRow[] | null>>;
	abstract getTransactionCurrencies(
		transactions: Pick<TransactionRow, 'currency'>[]
	): Promise<ReadResult<CurrencyRow[] | null>>;

	abstract getVenueSubmissions(venue: VenueID): Promise<ReadResult<SubmissionRow[] | null>>;
	abstract getScholarSubmissions(scholar: ScholarID): Promise<ReadResult<SubmissionRow[] | null>>;
	abstract getSubmission(id: SubmissionID): Promise<ReadResult<SubmissionRow | null>>;

	/** An author sends a single thank-you note to the reviewers of one of their
	 * (done) submissions. The note is held for venue vetting unless the venue has
	 * vetting off, in which case it is delivered immediately. Returns the
	 * resulting status so the UI can message "pending review" vs "sent".
	 * Delivery to reviewers happens server-side to preserve their anonymity. */
	abstract proposeThanks(
		submission: SubmissionID,
		message: string
	): Promise<Result<{ status: ThanksStatus }>>;
	/** A venue admin / editor approves a proposed thank-you note, delivering it. */
	abstract approveThanks(id: ThanksID): Promise<Result<undefined>>;
	/** A venue admin / editor declines a proposed thank-you note, with a reason. */
	abstract declineThanks(id: ThanksID, reason: string): Promise<Result<undefined>>;
	/** Thank-you notes for a submission, filtered by RLS to what the viewer may
	 * see (their own as author; all as a vetter; approved ones as a recipient). */
	abstract getSubmissionThanks(submission: SubmissionID): Promise<ReadResult<ThanksRow[] | null>>;
	abstract getPreviousSubmissionByID(id: SubmissionID): Promise<ReadResult<SubmissionRow[] | null>>;
	abstract getPreviousSubmissionByExternalID(
		venue: VenueID,
		externalID: string
	): Promise<ReadResult<SubmissionRow[] | null>>;
	abstract getScholarPriorSubmissions(
		venue: VenueID,
		scholar: ScholarID
	): Promise<
		ReadResult<Pick<SubmissionRow, 'id' | 'externalid' | 'title' | 'submission_type'>[] | null>
	>;
	abstract getVenueSubmissionExternalIDs(
		venue: VenueID
	): Promise<ReadResult<Pick<SubmissionRow, 'externalid'>[] | null>>;
	abstract getVenueSubmissionCount(venue: VenueID): Promise<ReadResult<number | null>>;

	abstract getVenueSubmissionTypes(venue: VenueID): Promise<ReadResult<SubmissionType[] | null>>;
	abstract getCompensationByTypes(
		typeIDs: SubmissionTypeID[]
	): Promise<ReadResult<CompensationRow[] | null>>;
	abstract getVenuePreferenceLevels(
		venue: VenueID
	): Promise<ReadResult<PreferenceLevelRow[] | null>>;

	abstract getVenueVolunteers(venue: VenueID): Promise<ReadResult<VenueVolunteer[] | null>>;
	abstract getVenueSettingsVolunteers(
		venue: VenueID
	): Promise<ReadResult<VenueSettingsVolunteer[] | null>>;
	abstract getVenueCommitments(venue: VenueID): Promise<ReadResult<VenueCommitment[] | null>>;
	abstract getScholarVolunteering(
		scholar: ScholarID
	): Promise<ReadResult<ScholarVolunteering[] | null>>;
	abstract getVolunteersByRoles(roleIDs: RoleID[]): Promise<ReadResult<VolunteerRow[] | null>>;
	abstract getScholarActiveVolunteering(
		scholar: ScholarID,
		roleIDs: RoleID[]
	): Promise<ReadResult<VolunteerRow[] | null>>;
	/** A scholar's ACCEPTED volunteer records among the given roles, regardless of
	 * whether they are currently active. Distinct from getScholarActiveVolunteering
	 * on purpose: the submissions SELECT policy's bidder branch tests `accepted`
	 * only, so a check that mirrors that policy must not also require `active`. */
	abstract getScholarAcceptedVolunteering(
		scholar: ScholarID,
		roleIDs: RoleID[]
	): Promise<ReadResult<VolunteerRow[] | null>>;

	abstract getVenueAssignments(venue: VenueID): Promise<ReadResult<AssignmentRow[] | null>>;
	/** Which of a venue's submissions already have someone in its editor role. A boolean
	 * per submission rather than the assignment rows themselves, because the venue's
	 * editors can see its submissions but not its assignments. */
	abstract getVenueSubmissionEditors(
		venue: VenueID
	): Promise<ReadResult<{ submission: SubmissionID; has_editor: boolean }[] | null>>;
	abstract getSubmissionAssignments(
		submission: SubmissionID
	): Promise<ReadResult<AssignmentRow[] | null>>;
	abstract getVenueActiveAssignmentScholars(
		venue: VenueID
	): Promise<ReadResult<Pick<AssignmentRow, 'scholar'>[] | null>>;
	abstract getActiveAssignmentsForScholars(
		scholarIDs: ScholarID[]
	): Promise<ReadResult<Pick<AssignmentRow, 'scholar' | 'venue'>[] | null>>;
	abstract getScholarReviews(scholar: ScholarID): Promise<ReadResult<ScholarReview[] | null>>;
	abstract getAssignmentsForApproval(
		roleIDs: RoleID[]
	): Promise<ReadResult<AssignmentForApproval[] | null>>;
	abstract getAssignmentsAwaitingCompensation(
		roleIDs: RoleID[]
	): Promise<ReadResult<AssignmentAwaitingCompensation[] | null>>;

	abstract getScholarConflicts(scholar: ScholarID): Promise<ReadResult<ConflictRow[] | null>>;

	abstract getProposal(id: ProposalID): Promise<ReadResult<ProposalRow | null>>;
	abstract getUnassignedProposals(): Promise<ReadResult<ProposalRow[] | null>>;
	abstract getProposalSupporters(
		proposal: ProposalID
	): Promise<ReadResult<ProposalSupporter[] | null>>;
}
