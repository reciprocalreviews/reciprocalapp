import { type ScholarID } from '../../data/types';
import type Submission from '$lib/types/Submission';
import type { SubmissionID } from '$lib/types/Submission';
import type Database from './Database';

/** Mark a submission as archived and create compensation transactions for reviewers, meta-reviewers, and editors. */
export default async function closeSubmission(
	db: Database,
	submissionID: SubmissionID,
	reviewers: ScholarID[]
): Promise<Submission> {
	// Get the submission.
	const submission = await db.getSubmission(submissionID);

	// Compensate the reviewers.
	const reviewerPayments = await Promise.all(
		reviewers.map((reviewer) => {
			return db.createTransaction({
				id: crypto.randomUUID(),
				submissionID: submissionID,
				editorID: submission.editorID,
				scholarID: reviewer,
				amount: submission.compensation.review,
				purpose: 'review',
				description: 'Thank you for your review!',
				creationtime: Date.now(),
				approvaltime: Date.now()
			});
		})
	);

	// Compensate the meta-reviewer
	const metaPayment = await db.createTransaction({
		id: crypto.randomUUID(),
		submissionID: submissionID,
		editorID: submission.editorID,
		scholarID: submission.metaID,
		amount: submission.compensation.meta,
		purpose: 'meta',
		description: 'Thank you for your meta-review!',
		creationtime: Date.now(),
		approvaltime: Date.now()
	});

	// Compensate the editor
	const editorPayment = await db.createTransaction({
		id: crypto.randomUUID(),
		submissionID: submissionID,
		editorID: submission.editorID,
		scholarID: submission.editorID,
		amount: submission.compensation.edit,
		purpose: 'edit',
		description: 'Thank you for your meta-review!',
		creationtime: Date.now(),
		approvaltime: Date.now()
	});

	// Revise the submission.
	const newSubmission: Submission = {
		...submission,
		payment: [...reviewerPayments.map((trans) => trans.id), metaPayment.id, editorPayment.id]
	};
	await db.updateSubmission(newSubmission);

	return newSubmission;
}
