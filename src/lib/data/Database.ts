import { type ScholarID, type Scholar } from '../../data/types';
import type { SourceID } from '$lib/types/Source';
import type Source from '$lib/types/Source';
import type Submission from '$lib/types/Submission';
import type Transaction from '$lib/types/Transaction';
import type { Charge, TransactionID } from '$lib/types/Transaction';

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
	): Promise<{ scholar: Scholar; balance: number }[]>;

	/** Create the given scholar. If they already exist, throw an error. */
	abstract createScholar(scholar: Scholar): Promise<Scholar>;

	/** Given a scholar ID, get information about the scholar, except the scholar's transactions */
	abstract getScholar(scholarID: ScholarID): Promise<Scholar | null>;

	/** Update the given scholar */
	abstract updateScholar(scholar: Scholar): Promise<Scholar>;

	/** Get the balance of the scholar */
	abstract getScholarBalance(scholarID: ScholarID): Promise<number>;

	/** Insert a new transaction in the database */
	abstract createTransaction(transaction: Transaction): Promise<Transaction>;

	/** Get the transaction with the given id */
	abstract getTransaction(id: TransactionID): Promise<Transaction | null>;

	/** Get all of this scholar's transactions */
	abstract getScholarTransactions(id: ScholarID): Promise<Transaction[]>;
}
