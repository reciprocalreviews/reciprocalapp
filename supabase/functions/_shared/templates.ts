export type Email = {
	subject: string;
	paragraphs: string[];
	/**
	 * 1-based positions of arguments that are trusted, server-generated URLs and may
	 * therefore render as clickable links. Every other argument has its URL scheme
	 * defanged at substitution time (see `escapeArg`).
	 *
	 * Nearly all templates own their URLs in the prose itself and interpolate only path
	 * segments (`https://reciprocal.reviews/venue/$2`), so they need no entry here. The
	 * exception is a template whose whole link is an argument — and such an argument must
	 * be built by the database or the server, never accepted from a caller.
	 */
	urlArgs?: number[];
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
	},
	// Author thank-you notes to reviewers (#22). These are rendered in the app
	// layer like every other template, then fanned out to recipients by the
	// queue_thanks_emails RPC (which resolves recipients server-side to preserve
	// reviewer anonymity). $-args: see each method in SupabaseCRUD.
	ThanksPendingReview: {
		subject: 'A thank-you note awaits your review',
		paragraphs: [
			'An author submitted a thank-you note to share with the reviewers of a submission. Please review it before it is shared:',
			'https://reciprocal.reviews/venue/$1/submission/$2'
		]
	},
	ThanksReceived: {
		subject: 'You received thanks for your reviewing',
		paragraphs: [
			'An author of a submission you reviewed sent their thanks:',
			'"$1"',
			'Thank you for your reviewing work. You can view the submission here:',
			'https://reciprocal.reviews/venue/$2/submission/$3'
		]
	},
	ThanksDeclined: {
		subject: 'Your thank-you note was not shared',
		paragraphs: [
			'The thank-you note you submitted for a submission was reviewed and not approved for sharing.',
			'Reason given: $1',
			'You can review and revise it here:',
			'https://reciprocal.reviews/venue/$2/submission/$3'
		]
	},
	// Contact-email ownership verification (#27). Sent through the normal branded pipeline
	// directly to the (still unverified) candidate address — the one message we're allowed
	// to send to an unverified email. $1 is the verification URL.
	VerifyEmail: {
		subject: 'Verify your Reciprocal Reviews contact email',
		paragraphs: [
			'Confirm this address to receive Reciprocal Reviews notifications. This link expires in 15 minutes:',
			'$1',
			'If you did not request this, you can safely ignore this email.'
		],
		// $1 is the whole verification link, so it must stay clickable. It is safe to trust
		// because request_email_verification builds it inside the database from the
		// `site_url` vault secret and a token only the database knows — no part of it comes
		// from the caller.
		urlArgs: [1]
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

/**
 * Neutralize URL schemes so an argument cannot become a clickable link.
 *
 * Escaping alone is not enough: `paragraphsToHtml`
 * (supabase/functions/_shared/emailShell.ts) auto-links bare `https://` text when the
 * body is rendered, and no character in a URL needs escaping — so an argument carrying
 * `https://example.invalid` would arrive as a real anchor inside genuinely branded mail
 * from notifications@reciprocal.reviews. Since argument values can originate from
 * scholar-supplied content (venue titles, decline reasons, notes), that is a phishing
 * vector regardless of who is allowed to send.
 *
 * `https://x` becomes `https[:]//x` — the auto-link pattern requires a literal `://`, so
 * the text renders visibly but inertly. Templates opt specific positions out via
 * `urlArgs` when the argument is a server-generated link.
 */
function defangURLs(value: string): string {
	return value.replace(/\b(https?|ftp):\/\//gi, '$1[:]//');
}

export function renderEmail(
	template: EmailType,
	args: string[]
): { subject: string; message: string } {
	// Get the email template.
	const email = Emails[template];
	const urlArgs = new Set<number>((email as Email).urlArgs ?? []);

	// Substitute every `$n` in one pass. A single pass (rather than one `replace` per
	// argument) matters twice over: `String.replace` with a string needle replaces only
	// the FIRST occurrence, so a template mentioning `$1` twice would keep a literal
	// placeholder; and replacing `$1` before `$10` would corrupt the longer placeholder.
	// An unknown `$n` is left as written rather than becoming "undefined".
	const substitute = (text: string, transform: (value: string, position: number) => string) =>
		text.replace(/\$(\d+)/g, (placeholder, digits) => {
			const index = Number(digits) - 1;
			return index >= 0 && index < args.length
				? transform(args[index], Number(digits))
				: placeholder;
		});

	// The message is rendered as branded HTML at send time, so its args are HTML-escaped
	// and have their URL schemes defanged unless the template declares that position as a
	// trusted link. The subject is a plain-text email header — never linkified — so its
	// args are substituted raw.
	const subject = substitute(email.subject, (value) => value);
	const message = substitute(email.paragraphs.join('\n\n'), (value, position) =>
		urlArgs.has(position) ? escapeArg(value) : defangURLs(escapeArg(value))
	);

	// The "automated email" footer is added by the branded shell at send time
	// (supabase/functions/_shared/emailShell.ts), so it isn't appended here.

	return { subject, message };
}
