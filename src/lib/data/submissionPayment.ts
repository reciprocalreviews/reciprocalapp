/** Whether a submission's charges have been paid, and by whom not.
 *
 * Shared by the submissions list's payment column and the batch payment check, so
 * the two pages cannot disagree about what "paid" means. Pure: callers pass in the
 * transactions they could read.
 *
 * A charge is settled only when its transaction is `approved`. `create_submission`
 * approves the submitter's own charge on the spot, but a co-author's stays `proposed`
 * until they approve it, and may be `declined`. Counting any visible transaction as
 * paid told a venue admin -- who can see all of them -- that a submission was paid
 * while a co-author's charge was still waiting. */

/** A non-paying co-author's slot in `submission.transactions`. */
export const NULL_TRANSACTION = '00000000-0000-0000-0000-000000000000';

export type ChargeStatus = 'approved' | 'proposed' | 'declined';

/** One charged author's charge. `unknown` is a transaction the viewer could not read,
 * which can't be called paid. */
export type AuthorCharge = { author: string; status: ChargeStatus | 'unknown' };

/** The charges a submission made, in author order, skipping non-paying slots. */
export function charges(
	submission: { authors: string[]; transactions: string[] },
	transactions: ReadonlyMap<string, ChargeStatus>
): AuthorCharge[] {
	const result: AuthorCharge[] = [];
	submission.transactions.forEach((id, index) => {
		if (id === NULL_TRANSACTION) return;
		result.push({
			author: submission.authors[index] ?? '',
			status: transactions.get(id) ?? 'unknown'
		});
	});
	return result;
}

/** The fields of a submission the batch check reads. */
export type PaymentCheckSubmission = {
	id: string;
	venue: string;
	externalid: string;
	title: string;
	imported: boolean;
	authors: string[];
	transactions: string[];
};

/** What the batch check says about one manuscript ID. Every state but `missing`
 * carries the submission it found. */
export type PaymentCheck = { externalid: string } &
	/** No submission at the venue has this ID: the authors never submitted it here. */
	(
		| { state: 'missing' }
		/** Bulk-imported, so nobody was ever charged for it through this platform. */
		| { state: 'imported'; submission: PaymentCheckSubmission }
		/** Submitted, but nothing was charged (a zero-cost type). */
		| { state: 'free'; submission: PaymentCheckSubmission }
		/** Every charge is approved. */
		| { state: 'paid'; submission: PaymentCheckSubmission }
		/** At least one charge is not approved; `unsettled` names whose. */
		| { state: 'outstanding'; submission: PaymentCheckSubmission; unsettled: AuthorCharge[] }
	);

export type PaymentCheckState = PaymentCheck['state'];

/** Classify one manuscript ID, given the submission found for it (if any). */
export function classifyPayment(
	externalid: string,
	submission: PaymentCheckSubmission | undefined,
	transactions: ReadonlyMap<string, ChargeStatus>
): PaymentCheck {
	if (submission === undefined) return { externalid, state: 'missing' };
	const all = charges(submission, transactions);
	if (all.length === 0)
		return { externalid, state: submission.imported ? 'imported' : 'free', submission };
	const unsettled = all.filter((charge) => charge.status !== 'approved');
	return unsettled.length === 0
		? { externalid, state: 'paid', submission }
		: { externalid, state: 'outstanding', submission, unsettled };
}

/** States needing someone to write to come first, in the order an admin works through
 * them; settled ones last. */
const ORDER: Record<PaymentCheckState, number> = {
	missing: 0,
	outstanding: 1,
	imported: 2,
	paid: 3,
	free: 4
};

/** Classify every ID, ordered by state and otherwise in the order pasted. */
export function checkPayments(
	externalIDs: string[],
	submissions: PaymentCheckSubmission[],
	transactions: ReadonlyMap<string, ChargeStatus>
): PaymentCheck[] {
	const byID = new Map(submissions.map((s) => [s.externalid, s]));
	return externalIDs
		.map((id) => classifyPayment(id, byID.get(id), transactions))
		.map((check, index) => ({ check, index }))
		.sort((a, b) => ORDER[a.check.state] - ORDER[b.check.state] || a.index - b.index)
		.map(({ check }) => check);
}

/** The manuscript IDs in pasted text: one per line, or separated by commas, semicolons
 * or tabs, so a column copied from a spreadsheet or a comma-separated list both work.
 * Spaces are kept inside an ID, since some systems use them. Blanks and repeats are
 * dropped, keeping the first occurrence's position. */
export function parseManuscriptIDs(text: string): string[] {
	const seen = new Set<string>();
	for (const part of text.split(/[\r\n,;\t]+/)) {
		const id = part.trim();
		if (id.length > 0) seen.add(id);
	}
	return [...seen];
}
