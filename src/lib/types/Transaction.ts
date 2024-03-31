import type { ScholarID } from './Scholar';

export type TransactionID = string;
export type Purpose = 'submission' | 'review' | 'meta' | 'edit' | 'gift';

export type Charge = { scholar: string; payment: number };

type Transaction = {
	/** A UUID representing a transaction in history. */
	id: string;
	/** The submission to which this transaction is associated, if there is one, and null if it was not (e.g., gifts or compensation for editing labor). Enables auditing of all transactions associated with a submission. */
	submissionID: string | null;
	/** The scholar who created the transaction. Enables auditing. Should only be null for welcome transactions */
	editorID: ScholarID | null;
	/** The scholar whose token balance was adjusted. */
	scholarID: string;
	/** The number of tokens this transaction adds or subtracts to an author’s balance. Determined by the current cost or compensation of the source, depending on the type of transaction. */
	amount: number;
	/** The purpose of the transaction. This list of purposes could grow as we identify other purposes. */
	purpose: Purpose;
	/** A message from the scholar who created the transaction, describing the rationale for the transaction (e.g., “Thanks for reviewing”, or “Here’s a gift”). */
	description: string;
	/** A Unix timestamp indicating when the transaction was created. Enables auditing. */
	creationtime: number;
	/** A Unix timestamp indicating when the transaction was approved by the person whose balance it affected */
	approvaltime: number | null;
};

export type { Transaction as default };
