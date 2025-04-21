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
	type RoleRow
} from '../../data/types';
import type { Charge, TransactionID } from '$lib/types/Transaction';
import { getContext, setContext } from 'svelte';
import type Scholar from './Scholar.svelte';
import type { SubmissionID } from '$lib/types/Submission';
import type { AuthError, PostgrestError } from '@supabase/supabase-js';

export const DatabaseSymbol = Symbol('database');
export const NullUUID = '00000000-0000-0000-0000-000000000000';

export function getDB() {
	return getContext<CRUD>(DatabaseSymbol);
}

export function setDB(db: CRUD) {
	setContext(DatabaseSymbol, db);
}

export type DBError = { message: string; details?: PostgrestError | AuthError };
export type Result<Type = undefined> = { data?: Type; error?: DBError };

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
		charges: Charge[]
	): Promise<Result<SubmissionID>>;

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
	abstract verifyCharges(charges: Charge[]): Promise<true | Charge[] | undefined>;

	abstract registerScholar(scholar: ScholarRow): Scholar;

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
		size: number,
		message: string
	): Promise<Result<ProposalID>>;

	abstract editProposalTitle(venue: ProposalID, title: string): Promise<Result>;
	abstract editProposalCensus(venue: ProposalID, census: number): Promise<Result>;
	abstract editProposalEditors(venue: ProposalID, editors: string[]): Promise<Result>;
	abstract editProposalURL(venue: ProposalID, url: string): Promise<Result>;

	/** Delete a proposal venue */
	abstract deleteProposal(proposal: ProposalID): Promise<Result>;

	/** Approval a venue proposal */
	abstract approveProposal(proposal: ProposalID): Promise<Result<string>>;

	/** Add support for a proposal */
	abstract addSupporter(scholar: ScholarID, proposal: ProposalID, message: string): Promise<Result>;

	abstract editSupport(support: SupporterID, message: string): Promise<Result>;
	abstract deleteSupport(support: SupporterID): Promise<Result>;

	abstract updateCurrencyName(id: CurrencyID, name: string): Promise<Result>;
	abstract updateCurrencyDescription(id: CurrencyID, description: string): Promise<Result>;

	abstract editVenueDescription(id: VenueID, description: string): Promise<Result>;
	abstract editVenueEditors(id: VenueID, editors: string[]): Promise<Result>;
	abstract addVenueEditor(id: VenueID, emailOrORCID: string): Promise<Result>;
	abstract editVenueTitle(id: VenueID, title: string): Promise<Result>;
	abstract editVenueURL(id: VenueID, url: string): Promise<Result>;
	abstract editVenueWelcomeAmount(id: VenueID, amount: number): Promise<Result>;
	abstract editVenueEditorCompensation(id: VenueID, amount: number): Promise<Result>;
	abstract editVenueSubmissionCost(id: VenueID, amount: number): Promise<Result>;

	abstract createRole(id: VenueID, name: string): Promise<Result<RoleRow>>;
	abstract editRoleName(id: RoleID, name: string): Promise<Result>;
	abstract editRoleDescription(id: RoleID, description: string): Promise<Result>;
	abstract editRoleInvited(id: RoleID, on: boolean): Promise<Result>;
	abstract editRoleBidding(id: RoleID, bidding: boolean): Promise<Result>;
	abstract editRoleApprover(id: RoleID, approver: RoleID | null): Promise<Result>;
	abstract editRoleAmount(id: RoleID, amount: number): Promise<Result>;
	abstract reorderRole(role: RoleRow, roles: RoleRow[], direction: -1 | 1): Promise<Result>;
	abstract deleteRole(id: RoleID): Promise<Result>;

	abstract createVolunteer(
		scholarid: ScholarID,
		roleid: RoleID,
		accepted: boolean,
		compensate: boolean
	): Promise<Result<string>>;
	abstract updateVolunteerActive(id: VolunteerID, active: boolean): Promise<Result>;
	abstract updateVolunteerExpertise(id: VolunteerID, expertise: string): Promise<Result>;
	abstract inviteToRole(role: RoleID, emails: string[]): Promise<Result<string[]>>;
	abstract acceptRoleInvite(id: VolunteerID, response: Response): Promise<Result>;

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
	abstract approveAssignment(assignment: AssignmentID, approved: boolean): Promise<Result>;

	/** Create a new assignment record */
	abstract createAssignment(
		submission: SubmissionID,
		scholar: ScholarID,
		role: RoleID,
		bid: boolean
	): Promise<Result>;

	abstract deleteAssignment(assignment: AssignmentID): Promise<Result>;

	abstract emailScholar(subject: string, message: string): Promise<Result>;
}
