import type { SourceID } from './Source';
import type { TransactionID } from './Transaction';

export type ScholarID = string;

export const ORCIDRegex = /^[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{4}$/;

type Scholar = {
	/** The author’s ORCID ID. Allows us to link transactions to specific scholars. */
	id: ScholarID;
	/** Author supplied full name, for display. Cached from ORCID periodically. Allows us to display author names when appropriate. */
	name: string;
	/** A set of keywords describing research activities. For use in search, filtering, and analytics. Cached from ORCID periodically. Allows us to support searching and filtering of scholars. */
	expertise: string[];
	/** Whether the author is explicitly seeking reviews. */
	reviewing: boolean;
	/** The number of tokens below which the author should be listed as seeking reviews, if they are explicitly seeking reviews. Allows public signaling of desire to review. */
	minimum: number;
	/** A list of Source ids for which the author has volunteered to review. */
	sources: SourceID[];
	/** A Unix timestamp indicating the time at which they created their account. Allows for auditing. */
	creationtime: number;
	/** A history of transaction IDs. Enables record of history of transactions that affect an author’s balance. */
	transactions: TransactionID[];
};

export type { Scholar as default };
