import type { SourceID } from '$lib/types/Source';
import type Cost from './Cost';
import type { ScholarID } from './Scholar';
import type { TransactionID } from './Transaction';

type SubmissionID = string;

type Submission = {
	/** A UUID representing a globally unique submission. Enables individual submissions to be tracked. */
	id: SubmissionID;
	/** The source to which the submission was submitted. Enables queries on a source’s submissions. */
	sourceID: SourceID;
	/** An ID from the external submission management system, not necessarily unique to the platform, but used to associate the entry with the review. Enables mapping from platform submission IDs to external reviewing system IDs. */
	externalID: string;
	/** The editor for this submission */
	editorID: ScholarID;
	/** The meta-reviewer for this submission */
	metaID: ScholarID;
	/** The title of the submission */
	title: string;
	/** Transactions for this submission authors */
	charges: TransactionID[];
	/** Compensation at the time of submission */
	compensation: Cost;
	/** Whether this submission is archived, meaning its no longer eligible for volunteering. */
	payment: null | TransactionID[];
	/** A Unix timestamp indicating when the submission was entered into the system. */
	creationtime: number;
};

export type { SubmissionID, Submission as default };
