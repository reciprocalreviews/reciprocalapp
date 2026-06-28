export type Email = {
	subject: string;
	paragraphs: string[];
};

export const Emails = {
	VenueApproved: {
		subject: 'Your venue has been approved',
		paragraphs: [
			'The venue "$1" has been approved and is now live on Reciprocal Reviews!',
			'If you are an editor, you can configure it with your reviewing platform:',
			'https://reciprocal.reviews/venue/$2',
			"If you're a supporter, the editors will likely communicate the timeline for launch separately."
		]
	},
	ProposalCreatedStewards: {
		subject: 'New venue proposal',
		paragraphs: [
			'A proposal was created for "$1".',
			'Review it and discuss it with the other stewards:',
			'https://reciprocal.reviews/venues/proposal/$2',
			'Consider reachnig out to the proposals to discuss the proposal further.'
		]
	},
	ProposalCreatedEditors: {
		subject: 'Proposal created for your academic venue',
		paragraphs: [
			'A proposal was created for your academic venue "$1" to help make its peer review more sustainable:',
			'https://reciprocal.reviews/venues/proposal/$2',
			"Learn more about Reciprocal Reviews to see if it's a good fit for your academic community.",
			'https://reciprocal.reviews'
		]
	},
	AssignmentApproved: {
		subject: 'Your are assigned a submission',
		paragraphs: [
			'<a href="mailto:$2">$1</a> assigned you as $3 for this submission:',
			'https://reciprocal.reviews/venue/$4/submission/$5',
			'Complete your assignment and you will receive compensation.'
		]
	},
	AssignmentRemoved: {
		subject: 'You were removed from a submission',
		paragraphs: [
			'<a href="mailto:$2">$1</a> removed you as $3 for this submission:',
			'https://reciprocal.reviews/venue/$4/submission/$5'
		]
	},
	RoleInvite: {
		subject: 'You were invited to a reviewing role',
		paragraphs: [
			'You have been invited to the $1 role for <a href="https://reciprocal.reviews/venue/$2">$3</a>. You can accept or decline on your profile:',
			'https://reciprocal.reviews/scholar/$4'
		]
	},
	CompensationRequested: {
		subject: 'Compensation requested for volunteer work',
		paragraphs: [
			"A scholar requested compensation for <a href='https://reciprocal.reviews/venue/$1/submission/$2'>this submission</a>. Here's the note they included:",
			'"$3"',
			"If this is a valid request, approve the assignment, evaluate their work, and if it meets your venue's standards, mark the work complete so they are compensated."
		]
	},
	WorkCompensated: {
		subject: 'You were paid for your $1 work',
		paragraphs: [
			'The approver of your $1 assignment marked your work complete and paid you $2 tokens for it. The tokens have been transferred to your account.',
			'You can view the submission here: https://reciprocal.reviews/venue/$3/submission/$4'
		]
	},
	VenueOutOfTokens: {
		subject: '$5 needs more tokens to pay its reviewers',
		paragraphs: [
			'An approver at $5 tried to pay $1 tokens for $2 work on a submission, but the venue is short $3 tokens.',
			'A proposed mint transaction sized exactly to the shortfall has been recorded so if you decide to approve it, it is a one click approval. If you approve it, then approver can retry the payment:',
			'https://reciprocal.reviews/venue/$4/transactions'
		]
	},
	TransactionDeclinedVenue: {
		subject: 'Your transaction was declined',
		paragraphs: [
			'Your proposed transaction for <strong>$2</strong> $3 tokens at <strong>$4</strong> — "$1" — was declined by <a href="mailto:$6">$5</a>.',
			'Reason given: $7',
			'You can review and follow up on this here: $8'
		]
	},
	TransactionDeclined: {
		subject: 'Your transaction was declined',
		paragraphs: [
			'Your proposed transaction for <strong>$2</strong> $3 tokens — "$1" — was declined by <a href="mailto:$5">$4</a>.',
			'Reason given: $6',
			'You can review and follow up on this here: $7'
		]
	}
} satisfies Record<string, Email>;

export type EmailType = keyof typeof Emails;

/**
 * Escape a value for safe inclusion in HTML. The message bodies are later
 * wrapped in a branded HTML shell (supabase/functions/_shared/emailShell.ts)
 * before being sent, and the templates themselves embed intentional markup
 * (<a>, <strong>). Argument values, however, can carry user-supplied content
 * (venue titles, decline reasons, etc.), so we escape them at substitution time
 * so they render as text rather than markup.
 */
function escapeArg(value: string): string {
	return value
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&#39;');
}

export function renderEmail(
	template: EmailType,
	args: string[]
): { subject: string; message: string } {
	// Get the email template.
	const email = Emails[template];
	let subject = email.subject;
	let message = email.paragraphs.join('\n\n');

	// Go through each provided arg and replace it in the email subject and message.
	// The message is rendered as branded HTML at send time, so its args are
	// HTML-escaped; the subject is a plain-text email header, so its args are
	// substituted raw.
	for (let argIndex = 0; argIndex < args.length; argIndex++) {
		const placeholder = `$${argIndex + 1}`;
		subject = subject.replace(placeholder, args[argIndex]);
		message = message.replace(placeholder, escapeArg(args[argIndex]));
	}

	// The "automated email" footer is added by the branded shell at send time
	// (supabase/functions/_shared/emailShell.ts), so it isn't appended here.

	return { subject, message };
}
