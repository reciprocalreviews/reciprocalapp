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
import type { Charge, TransactionID } from '$lib/types/Transaction';
import { getContext, setContext } from 'svelte';
import type Scholar from './Scholar.svelte';
import type { SubmissionID } from '$lib/types/Submission';

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
	UndeletedTransaction: "The proposed transaction couldn't be deleted.",
	InvalidCharges: "The proposed transaction's charges are invalid.",
	NewSubmission: 'Unable to create a new submission',
	UpdateSubmissionExpertise: 'Unable to update the submission expertise',
	UpdateSubmissionTitle: "Unable to update the submission's title"
};

export type ErrorID = keyof typeof Errors;

/** This abstract class defines an interface for database access. It's useful for defining mocks as well as enables us to change databases if necessary. */
export default abstract class CRUD {
	/** Insert a new submission in the database */
	abstract createSubmission(
		editor: ScholarID,
		title: string,
		expertise: string,
		venue: VenueID,
		externalID: string,
		previousID: string | null,
		charges: Charge[],
		message: string
	): Promise<undefined | ErrorID>;

	/** Given a submission ID, update it's data. */
	abstract updateSubmissionExpertise(
		submissionID: SubmissionID,
		expertise: string | null
	): Promise<ErrorID | undefined>;

	abstract updateSubmissionTitle(
		submissionID: SubmissionID,
		title: string | null
	): Promise<ErrorID | undefined>;

	/** Check whether the given scholars have enough tokens for the given payments. True if so, and a list of remaining balances by scholar if not. */
	abstract verifyCharges(charges: Charge[]): Promise<true | Charge[] | undefined>;

	abstract registerScholar(scholar: ScholarRow): Scholar;

	/** Given a scholar ID, get information about the scholar, except the scholar's transactions */
	abstract getScholar(scholarID: ScholarID): Promise<Scholar | null>;

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
