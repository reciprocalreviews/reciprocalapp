import type { ScholarID } from '../../data/types';
import type { SourceID } from '$lib/types/Source';
import type Submission from '$lib/types/Submission';
import type Transaction from '$lib/types/Transaction';
import type Database from './Database';

/** Create a submission and associated transactions */
export default async function createSubmission(
	db: Database,
	sourceID: SourceID,
	editorID: ScholarID,
	metaID: ScholarID,
	title: string,
	externalID: string,
	charges: { scholar: string; payment: number }[]
): Promise<Submission> {
	// Get the source
	const source = await db.getSource(sourceID);

	// Make the ID for the submission.
	const submissionID = crypto.randomUUID();

	// Make the transactions.
	const transactions: Transaction[] = charges.map((charge) => {
		return {
			id: crypto.randomUUID(),
			submissionID: submissionID,
			editorID,
			scholarID: charge.scholar,
			amount: -charge.payment,
			purpose: 'submission',
			description: 'Thank you for your submission!',
			creationtime: Date.now(),
			approvaltime: null
		};
	});

	// Make submission.
	const submission: Submission = {
		id: submissionID,
		sourceID,
		externalID,
		editorID,
		metaID,
		title,
		charges: transactions.map((trans) => trans.id),
		compensation: source.cost,
		payment: transactions.map((trans) => trans.id),
		creationtime: Date.now()
	};

	// Save them.
	await db.createSubmission(submission);
	await Promise.all(transactions.map((trans) => db.createTransaction(trans)));

	return submission;
}
