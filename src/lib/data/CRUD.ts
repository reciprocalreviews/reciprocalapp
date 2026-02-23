import {
	type CurrencyID,
	type ProposalID,
	type RoleID,
	type ScholarID,
	type ScholarRow,
	type SupporterID,
	type VenueID,
	type VolunteerID,
	type Response,
	type TokenID,
	type TransactionStatus,
	type AssignmentID,
	type SubmissionStatus,
	type RoleRow,
	type AssignmentRow,
	type VenueRow,
	type SubmissionID,
	type TransactionID,
	type SubmissionTypeID,
	type SubmissionType,
	type CompensationRow
} from '../../data/types';
import { getContext, setContext } from 'svelte';
import type Scholar from './Scholar.svelte';
import type { AuthError, PostgrestError } from '@supabase/supabase-js';
import type { EmailType } from '../../email/templates';
import type SupabaseCRUD from './SupabaseCRUD.svelte';

export const DatabaseSymbol = Symbol('database');
export const NullUUID = '00000000-0000-0000-0000-000000000000';

export function getDB(): () => SupabaseCRUD {
	return getContext<() => SupabaseCRUD>(DatabaseSymbol);
}

export function setDB(db: () => SupabaseCRUD) {
	setContext(DatabaseSymbol, db);
}

export type DBError = { message: string; details?: PostgrestError | AuthError };
export type Result<Type = undefined> = { data?: Type; error?: DBError };

export type Charge = { scholar: string; payment: number | undefined };

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
		submission_type: SubmissionTypeID,
		charges: Charge[]
	): Promise<Result<SubmissionID>>;

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

	/** Toggle the submission stats */
	abstract updateSubmissionStatus(
		submissionID: SubmissionID,
		status: SubmissionStatus
	): Promise<Result>;

	/** Check whether the given scholars have enough tokens for the given payments. True if so, and a list of remaining balances by scholar if not. */
	abstract verifyCharges(charges: Charge[]): Promise<Result<true | Charge[] | undefined>>;

	abstract registerScholar(scholar: ScholarRow): Scholar;

	abstract findScholar(emailOrORCID: string): Promise<Result<ScholarID | undefined>>;

	/** Given a scholar ID, get information about the scholar, except the scholar's transactions */
	abstract getScholar(scholarID: ScholarID): Promise<Scholar | null>;

	/** Update scholar's name */
	abstract updateScholarName(id: ScholarID, name: string): Promise<Result>;

	/** Update scholar's availabilty */
	abstract updateScholarAvailability(id: ScholarID, available: boolean): Promise<Result>;

	/** Update scholar's reviewing status. */
	abstract updateScholarStatus(id: ScholarID, status: string): Promise<Result>;

	/** Update scholar's reviewing status. */
	abstract updateScholarEmail(id: ScholarID, email: string): Promise<Result>;

	/** Propose a venue */
	abstract proposeVenue(
		scholar: ScholarID,
		venue: string,
		url: string,
		editors: string[],
		currency: CurrencyID | null,
		minters: string[],
		size: number,
		message: string
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
	abstract editVenueInactive(id: VenueID, inactive: string | null): Promise<Result>;
	abstract editVenueAnonymousAssignments(id: VenueID, anonymous: boolean): Promise<Result>;
	abstract editVenueWelcomeAmount(id: VenueID, amount: number): Promise<Result>;
	abstract editVenueSubmissionCost(id: VenueID, amount: number): Promise<Result>;

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
		revision: SubmissionTypeID | null
	): Promise<Result<SubmissionType>>;

	abstract editSubmissionType(
		id: SubmissionTypeID,
		name: string,
		description: string,
		revision: SubmissionTypeID | null
	): Promise<Result>;

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
		compensate: boolean
	): Promise<Result<string>>;

	abstract welcomeVolunteer(
		welcomer: ScholarID,
		scholar: ScholarID,
		roleid: RoleID,
		reason: string
	): Promise<Result>;

	abstract updateVolunteerActive(id: VolunteerID, active: boolean): Promise<Result>;
	abstract updateVolunteerExpertise(id: VolunteerID, expertise: string): Promise<Result>;
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

	abstract mintTokens(id: CurrencyID, amount: number, to: VenueID): Promise<Result>;

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

	/** Mark the transaction canceled */
	abstract cancelTransaction(id: TransactionID, reason: string): Promise<Result>;

	/** Update an assignment for a submission */
	abstract approveAssignment(
		assignment: AssignmentRow,
		approved: boolean,
		role: RoleRow,
		approver: ScholarID
	): Promise<Result>;

	/** Create a new assignment record */
	abstract createAssignment(
		submission: SubmissionID,
		scholar: ScholarID,
		role: RoleID,
		bid: boolean,
		approved?: boolean
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

	/** Send an email with the given subject and message to the authenticated scholar. */
	abstract emailScholars(scholars: ScholarID[], event: EmailType, args: string[]): Promise<Result>;

	/** Send an email to people without scholar accounts */
	abstract sendEmail(
		emails: string[] | { id: ScholarID; email: string }[],
		template: EmailType,
		args: string[]
	): Promise<Result>;

	/** Add a conflict */
	abstract declareConflict(
		scholar: ScholarID,
		submission: SubmissionID,
		reason: string
	): Promise<Result>;
}
