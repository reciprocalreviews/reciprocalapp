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
		subject: 'Your assignment has been approved',
		paragraphs: [
			'<a href="mailto:$2">$1</a> assigned you as $3 for this submission:',
			'https://reciprocal.reviews/submission/$4',
			'Complete your assignment and you will receive compensation.'
		]
	},
	AssignmentRemoved: {
		subject: 'You were removed from a submission',
		paragraphs: [
			'<a href="mailto:$2">$1</a> removed you as $3 for this submission:',
			'https://reciprocal.reviews/submission/$4'
		]
	}
} satisfies Record<string, Email>;

export type EmailType = keyof typeof Emails;

export function renderEmail(
	template: EmailType,
	args: string[]
): { subject: string; message: string } {
	// Get the email template.
	const email = Emails[template];
	let subject = email.subject;
	let message = email.paragraphs.join('\n\n');

	// Go through each provided arg and replace it in the email subject and message.
	for (let argIndex = 0; argIndex < args.length; argIndex++) {
		subject = subject.replace(`$${argIndex + 1}`, args[argIndex]);
		message = message.replace(`$${argIndex + 1}`, args[argIndex]);
	}

	// Append a footer to the message.

	message += `\n\n---\n\nThis is an automated email sent by Reciprocal Reviews.`;

	return { subject, message };
}
