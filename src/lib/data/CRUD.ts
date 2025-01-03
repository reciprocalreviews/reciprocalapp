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
	type TransactionStatus
} from '../../data/types';
import type { SourceID } from '$lib/types/Source';
import type Source from '$lib/types/Source';
import type Submission from '$lib/types/Submission';
import type Transaction from '$lib/types/Transaction';
import type { Charge, TransactionID } from '$lib/types/Transaction';
import { getContext, setContext } from 'svelte';
import type Scholar from './Scholar.svelte';

export const DatabaseSymbol = Symbol('database');
export const NullUUID = '00000000-0000-0000-0000-000000000000';

export function getDB() {
	return getContext<CRUD>(DatabaseSymbol);
}

export function setDB(db: CRUD) {
	setContext(DatabaseSymbol, db);
}

/** The strings for the email errors */
export const Errors = {
	UpdateScholarStatus: 'Unable to update your status',
	UpdateScholarName: 'Unable to update your name',
	UpdateScholarEmail: 'Unable to update your email',
	UpdateScholarAvailability: 'Unable to update your availability',
	CreateProposal: 'Unable to create a venue proposal',
	EditProposalTitle: 'Unable to edit the proposal title',
	EditProposalCensus: 'Unable to edit the proposal census',
	EditProposalEditors: 'Unable to edit the proposal editors',
	EditProposalURL: 'Unable to edit the proposal URL',
	CreateSupporter: 'Unable to create a supporter',
	UpdateCurrencyName: 'Unable to update the currency name',
	UpdateCurrencyDescription: 'Unable to update the currency description',
	EditSupport: 'Unable to edit your support',
	RemoveSupport: 'Unable to remove your support',
	DeleteProposal: 'Unable to delete the proposal',
	ApproveProposalNotFound: "Unable to approve the proposal: couldn't find proposal.",
	ApproveProposalNoScholars:
		"Unable to approve the proposal: couldn't find any of the specified editors with accounts. As them to create accounts with the specified email addresses and then approve.",
	ApproveProposalNoVenue: "Unable to approve the proposal: couldn't create the venue.",
	ApproveProposalCannotUpdateVenue:
		"Unable to approve the proposal: couldn't update the venue with the proposal.",
	ApproveProposalNoCurrency:
		"Unable to approve the proposal: couldn't create a currency for the venue.",
	EditVenueDescription: 'Unable to edit the venue description',
	EditVenueEditors: 'Unable to edit the venue editors',
	EditVenueAddEditorVenueNotFound: 'Unable to find venue',
	ScholarNotFound: 'Unable to find scholar by this email or ORCID',
	EditVenueAddEditorAlreadyEditor: 'Scholar is already an editor',
	EditVenueTitle: 'Unable to edit the venue title',
	EditVenueURL: 'Unable to edit the venue URL',
	EditVenueWelcomeAmount: 'Unable to edit the welcome amount',
	EditVenueSubmissionCost: 'Unable to edit the submission cost',
	EditVenueBidding: 'Unable to toggle bidding',
	CreateRole: 'Unable to create new role.',
	UpdateRoleName: 'Unable to update role name',
	UpdateRoleDescription: 'Unable to update role description',
	UpdateRoleInvited: 'Unable to update invited status of role',
	UpdateRoleAmount: 'Unable to update role compensation',
	DeleteRole: 'Unable to delete role',
	CreateVolunteer: 'Unable to add volunteer commitment',
	AlreadyVolunteered: 'Already created a volunteer commitment for this role.',
	UpdateVolunteerActive: 'Unable to update volunteer commitment',
	UpdateVolunteerExpertise: 'Unable to update your expertise',
	InviteToRole: 'Unable to invite to role',
	AcceptRoleInvite: 'Unable to accept role invite',
	EditCurrencyMinters: 'Unable to edit minters',
	AddCurrencyMinter: 'Unable to add minter',
	AlreadyMinter: 'This scholar is already a minter',
	MintTokens: 'Unable to mint tokens',
	TransferVenueTokens: 'Unable to transfer tokens',
	TransferScholarTokens: 'Unable to find scholar tokens to transfer',
	TransferTokensInsufficient: 'Insufficient number tokens to transfer',
	CreateTransaction: 'Unable to create transaction',
	UnknownTransaction: 'Unable to find this transaction',
	AlreadyApproved: 'This transaction is already approved',
	MissingApprovalVenue: 'The proposed transaction has no venue to transfer from.',
	MissingRecipient: 'The proposed transaction has no scholar recipient.',
	UndeletedTransaction: "The proposed transaction couldn't be deleted."
};

export type ErrorID = keyof typeof Errors;

/** This abstract class defines an interface for database access. It's useful for defining mocks as well as enables us to change databases if necessary. */
export default abstract class CRUD {
	/** Insert a new submission in the database */
	abstract createSubmission(submission: Submission): Promise<Submission>;

	/** Given a submission ID, eventually return the submission data. */
	abstract getSubmission(submissionID: string): Promise<Submission>;

	/** Given a submission ID, update it's data. */
	abstract updateSubmission(submission: Submission): Promise<Submission>;

	/** Check whether the given scholars have enough tokens for the given payments. True if so, and a list of remaining balances by scholar if not. */
	abstract verifyCharges(charges: Charge[]): Promise<true | Charge[]>;

	/** Create a new source in the database with the given scholar ID as an editor */
	abstract createSource(source: Source): Promise<Source>;

	/** Given a source ID, eventually return the source data. */
	abstract getSource(sourceID: string): Promise<Source>;

	/** Get all sources in the database */
	abstract getSources(): Promise<Source[]>;

	/** Get all sources a scholar edits */
	abstract getEditedSources(editor: ScholarID): Promise<Source[]>;

	/** Update the given source */
	abstract updateSource(source: Source): Promise<Source>;

	/** Given a source ID, eventually return all active submissions submitted to that source */
	abstract getActiveSubmissions(sourceID: SourceID): Promise<Submission[]>;

	/** Given a source ID, eventually return all scholars who have volunteered to review */
	abstract getSourceVolunteers(
		sourceID: SourceID
	): Promise<{ scholar: ScholarRow; balance: number }[]>;

	abstract registerScholar(scholar: ScholarRow): Scholar;

	/** Create the given scholar. If they already exist, throw an error. */
	abstract createScholar(scholar: ScholarRow): Promise<ScholarRow>;

	/** Given a scholar ID, get information about the scholar, except the scholar's transactions */
	abstract getScholar(scholarID: ScholarID): Promise<Scholar | null>;

	/** Update the given scholar */
	abstract updateScholar(scholar: ScholarRow): Promise<ScholarRow>;

	/** Update scholar's name */
	abstract updateScholarName(id: ScholarID, name: string): Promise<ErrorID | undefined>;

	/** Update scholar's availabilty */
	abstract updateScholarAvailability(
		id: ScholarID,
		available: boolean
	): Promise<ErrorID | undefined>;

	/** Update scholar's reviewing status. */
	abstract updateScholarStatus(id: ScholarID, status: string): Promise<ErrorID | undefined>;

	/** Update scholar's reviewing status. */
	abstract updateScholarEmail(id: ScholarID, email: string): Promise<ErrorID | undefined>;

	/** Get the balance of the scholar */
	abstract getScholarBalance(scholarID: ScholarID): Promise<number>;

	/** Get the transaction with the given id */
	abstract getTransaction(id: TransactionID): Promise<Transaction | null>;

	/** Get all of this scholar's transactions */
	abstract getScholarTransactions(id: ScholarID): Promise<Transaction[]>;

	/** Propose a venue */
	abstract proposeVenue(
		scholar: ScholarID,
		venue: string,
		url: string,
		editors: string[],
		size: number,
		message: string
	): Promise<ProposalID | ErrorID>;

	abstract editProposalTitle(venue: ProposalID, title: string): Promise<ErrorID | undefined>;
	abstract editProposalCensus(venue: ProposalID, census: number): Promise<ErrorID | undefined>;
	abstract editProposalEditors(venue: ProposalID, editors: string[]): Promise<ErrorID | undefined>;
	abstract editProposalURL(venue: ProposalID, url: string): Promise<ErrorID | undefined>;

	/** Delete a proposal venue */
	abstract deleteProposal(proposal: ProposalID): Promise<ErrorID | undefined>;

	/** Approval a venue proposal */
	abstract approveProposal(proposal: ProposalID): Promise<ErrorID | undefined>;

	/** Add support for a proposal */
	abstract addSupporter(
		scholar: ScholarID,
		proposal: ProposalID,
		message: string
	): Promise<ErrorID | undefined>;

	abstract editSupport(support: SupporterID, message: string): Promise<ErrorID | undefined>;
	abstract deleteSupport(support: SupporterID): Promise<ErrorID | undefined>;

	abstract updateCurrencyName(id: CurrencyID, name: string): Promise<ErrorID | undefined>;
	abstract updateCurrencyDescription(
		id: CurrencyID,
		description: string
	): Promise<ErrorID | undefined>;

	abstract editVenueDescription(id: VenueID, description: string): Promise<ErrorID | undefined>;
	abstract editVenueEditors(id: VenueID, editors: string[]): Promise<ErrorID | undefined>;
	abstract addVenueEditor(id: VenueID, emailOrORCID: string): Promise<ErrorID | undefined>;
	abstract editVenueTitle(id: VenueID, title: string): Promise<ErrorID | undefined>;
	abstract editVenueURL(id: VenueID, url: string): Promise<ErrorID | undefined>;
	abstract editVenueWelcomeAmount(id: VenueID, amount: number): Promise<ErrorID | undefined>;
	abstract editVenueSubmissionCost(id: VenueID, amount: number): Promise<ErrorID | undefined>;
	abstract editVenueBidding(id: VenueID, bidding: boolean): Promise<ErrorID | undefined>;

	abstract createRole(id: VenueID, name: string): Promise<ErrorID | undefined>;
	abstract editRoleName(id: RoleID, name: string): Promise<ErrorID | undefined>;
	abstract editRoleDescription(id: RoleID, description: string): Promise<ErrorID | undefined>;
	abstract editRoleInvited(id: RoleID, on: boolean): Promise<ErrorID | undefined>;
	abstract editRoleAmount(id: RoleID, amount: number): Promise<ErrorID | undefined>;
	abstract deleteRole(id: RoleID): Promise<ErrorID | undefined>;

	abstract createVolunteer(
		scholarid: ScholarID,
		roleid: RoleID,
		accepted: boolean,
		compensate: boolean
	): Promise<ErrorID | undefined>;
	abstract updateVolunteerActive(id: VolunteerID, active: boolean): Promise<ErrorID | undefined>;
	abstract updateVolunteerExpertise(
		id: VolunteerID,
		expertise: string
	): Promise<ErrorID | undefined>;
	abstract inviteToRole(role: RoleID, emails: string[]): Promise<ErrorID | undefined>;
	abstract acceptRoleInvite(id: VolunteerID, response: Response): Promise<ErrorID | undefined>;

	abstract editCurrencyMinters(id: CurrencyID, minters: string[]): Promise<ErrorID | undefined>;
	abstract addCurrencyMinter(
		id: CurrencyID,
		minters: string[],
		emailOrORCID: string
	): Promise<ErrorID | undefined>;

	abstract mintTokens(id: CurrencyID, amount: number, to: VenueID): Promise<ErrorID | undefined>;

	abstract transferTokens(
		scholar: ScholarID,
		from: VenueID,
		fromKind: 'venueid' | 'scholarid' | 'emailorcid',
		to: string,
		toKind: 'venueid' | 'scholarid' | 'emailorcid',
		amount: number,
		purpose: string
	): Promise<ErrorID | undefined>;

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
	): Promise<ErrorID | undefined>;

	/**
	 * Given a transaction ID that is pending, creators or transfers tokens based on the transaction.
	 * Will only work for a currency's minter because of security rules.
	 * */
	abstract approveTransaction(minter: ScholarID, id: TransactionID): Promise<ErrorID | undefined>;
}
