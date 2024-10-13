import {
	type CurrencyID,
	type ProposalID,
	type ScholarID,
	type ScholarRow,
	type SupporterID
} from '../../data/types';
import type { SourceID } from '$lib/types/Source';
import type Source from '$lib/types/Source';
import type Submission from '$lib/types/Submission';
import type Transaction from '$lib/types/Transaction';
import type { Charge, TransactionID } from '$lib/types/Transaction';
import { getContext, setContext } from 'svelte';
import type Scholar from './Scholar.svelte';

export const DatabaseSymbol = Symbol('database');

export function getDB() {
	return getContext<Database>(DatabaseSymbol);
}

export function setDB(db: Database) {
	setContext(DatabaseSymbol, db);
}

/** The strings for the email errors */
export const Errors = {
	UpdateScholarStatus: 'Unable to update your status',
	UpdateScholarName: 'Unable to update your name',
	UpdateScholarEmail: 'Unable to update your email',
	UpdateScholarAvailability: 'Unable to update your availability',
	CreateProposal: 'Unable to create a venue proposal',
	CreateSupporter: 'Unable to create a supporter',
	UpdateCurrencyName: 'Unable to update the currency name',
	UpdateCurrencyDescription: 'Unable to update the currency description',
	EditSupport: 'Unable to edit your support',
	RemoveSupport: 'Unable to remove your support',
	DeleteProposal: 'Unable to delete the proposal'
};

export type ErrorID = keyof typeof Errors;

/** This abstract class defines an interface for database access. It's useful for defining mocks as well as enables us to change databases if necessary. */
export default abstract class Database {
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

	/** Insert a new transaction in the database */
	abstract createTransaction(transaction: Transaction): Promise<Transaction>;

	/** Get the transaction with the given id */
	abstract getTransaction(id: TransactionID): Promise<Transaction | null>;

	/** Get all of this scholar's transactions */
	abstract getScholarTransactions(id: ScholarID): Promise<Transaction[]>;

	/** Propose a venue */
	abstract proposeVenue(
		scholar: ScholarID,
		venue: string,
		editors: string[],
		size: number,
		message: string
	): Promise<ProposalID | ErrorID>;

	/** Delete a proposal venue */
	abstract deleteProposal(proposal: ProposalID): Promise<ErrorID | undefined>;

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
}
