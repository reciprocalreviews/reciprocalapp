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
	ProposalCreated: {
		subject: 'New venue proposal',
		paragraphs: [
			'A proposal was created for "$1".',
			'Review it and discuss it with the other stewards:',
			'https://reciprocal.reviews/venues/proposal/$2',
			'Consider reachnig out to the proposals to discuss the proposal further.'
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
