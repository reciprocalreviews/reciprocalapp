export type Email = {
	subject: string;
	paragraphs: string[];
	/**
	 * 1-based positions of arguments that are trusted, server-generated URLs and may
	 * therefore render as clickable links. Every other argument has its URL scheme
	 * defanged at substitution time (see `escapeArg`).
	 *
	 * Nearly all templates own their URLs in the prose itself and interpolate only path
	 * segments (`{origin}/venue/$2`), so they need no entry here. The
	 * exception is a template whose whole link is an argument — and such an argument must
	 * be built by the database or the server, never accepted from a caller.
	 */
	urlArgs?: number[];
	/**
	 * The 1-based position of an argument holding a `BiddingDigestPayload` as JSON, rendered
	 * as a grouped list by `formatBiddingDigest` rather than substituted as text.
	 *
	 * A variable-length list cannot be one escaped argument (its links would be defanged) and
	 * cannot be pre-rendered by the producer (then the producer, not this registry, would own
	 * the markup and the escaping). So the list travels as data and is formatted here, at send
	 * time, where every scholar-supplied string is escaped and every link is built from the
	 * trusted origin.
	 */
	digestArg?: number;
	/**
	 * A courtesy notice a scholar may silence from their profile settings.
	 *
	 * Absent means the email is consequential — a charge, a decline, a verification, an
	 * assignment, a payout — and is always delivered; someone who has been billed does not
	 * get to opt out of being told. So this registry, not a list somewhere else, is the
	 * single source of truth for what can be turned off, and marking a template `optional`
	 * is the whole of adding a new preference. The key is what
	 * `public.notification_settings.event` holds, and the producer of an optional email is
	 * responsible for checking that table before queuing it.
	 */
	optional?: true;
	/**
	 * Silenceable under ANOTHER template's key, rather than under its own.
	 *
	 * Routing the reminder cron through this registry created duplicate news: the notice that
	 * a submission needs an editor, its plural form, and the reminder that chases it are one
	 * thing a reader cares about, and three checkboxes for it would be worse than the single
	 * checkbox this whole change set out to fix. So a template may defer to the preference of
	 * the template that owns the news. The target must itself be `optional`; a unit test
	 * asserts it, because a chain of deferrals would have no key at the end of it.
	 *
	 * Typed `string` rather than `EmailType`: `EmailType` is `keyof typeof Emails`, and
	 * `Emails` is checked against this very type, so naming it here is a circular reference
	 * TypeScript rejects outright (TS2502/TS2456). `AssertSilencedBy` below restores the
	 * constraint once `EmailType` exists, so a typo is still a compile error rather than a
	 * template that silently cannot be silenced.
	 */
	silencedBy?: string;
	/**
	 * Whether this preference is on for a scholar who has expressed no opinion. Absent means
	 * true.
	 *
	 * Only meaningful on a template that owns its key (`optional`). It exists because
	 * "absence of a row is the default, and the default is on" stops being a kindness once
	 * there are two dozen notices: a scholar who never opens their profile would be opted in
	 * to every one of them at once. A notice that is genuinely useful but too frequent to
	 * impose -- a bid arriving, a volunteer pausing -- ships `false` and waits to be asked
	 * for. Declared here rather than backfilled as rows, so adding a preference is still
	 * nothing but a mark on a template.
	 */
	defaultOn?: false;
	/**
	 * Which group of controls this preference appears under on the scholar profile. Required
	 * on a template that owns its key; a unit test asserts it, since a control with no
	 * section would not be rendered at all.
	 */
	section?: NotificationSection;
};

/**
 * The groups the profile's notification controls are rendered in, in display order. Scholars
 * hold several unrelated relationships to the platform at once -- they are paid, they review,
 * they run venues -- and two dozen controls in one undifferentiated column would be
 * unscannable. The keys are locale paths, not prose.
 */
export const NotificationSectionKeys = ['tokens', 'reviewing', 'venues', 'community'] as const;

export type NotificationSection = (typeof NotificationSectionKeys)[number];

export const Emails = {
	VenueApproved: {
		subject: 'Your venue has been approved',
		paragraphs: [
			'The venue "$1" has been approved and is now live on Reciprocal Reviews!',
			'If you are an editor, you can configure it with your reviewing platform:',
			'<rr-button href="{origin}/venue/$2">Open the venue</rr-button>',
			"If you're a supporter, the editors will likely communicate the timeline for launch separately."
		],
		// News about a proposal you made or backed. An editor has work to do here, but a
		// supporter has none at all, and the two share a template, so the courtesy reading
		// governs. `ProposalDeclined` defers to this key: outcome is one subscription.
		optional: true,
		section: 'community'
	},
	ProposalCreatedStewards: {
		subject: 'New venue proposal',
		paragraphs: [
			'A proposal was created for "$1".',
			'Review it and discuss it with the other stewards:',
			'<rr-button href="{origin}/venues/proposal/$2">Review the proposal</rr-button>',
			'Consider reachnig out to the proposals to discuss the proposal further.'
		]
	},
	ReconciliationFailed: {
		subject: 'Token ledger reconciliation failed',
		paragraphs: [
			'The nightly integrity check on the token ledger found problems at $1.',
			'$2',
			'This means the record of how tokens moved no longer agrees with the tokens themselves, so balances may be wrong. The cause is almost certainly a bug or a direct change to the database rather than anything a scholar did — no scholar can move tokens except through a recorded transaction.',
			'The full result is stored in the reconciliations table; the most recent row names which checks failed. supabase/dr/ has the tools for investigating, including tokens_as_of() for comparing current balances against any past moment.'
		]
	},
	// $1 the date (UTC), $2 how many volunteers due a digest were not reached. To the steward
	// inbox, from public.report_bidding_digest_backlog, run by cron after Monday's last digest run.
	BiddingDigestBacklog: {
		subject: 'The bidding digest did not reach everyone on $1',
		paragraphs: [
			'The Monday bidding digest ran out of time before it reached $2 volunteer(s) who were due one. They will be first in line next Monday, so nobody misses it twice, but they heard nothing this week.',
			"The digest sends about six emails a second, to stay under Resend's rate limit, in runs every five minutes from 12:00 to 15:55 UTC. If this happens again, the number of volunteers has outgrown that window: widen the bidding-digest-weekly schedule, or move the digest to Resend's batch endpoint. ARCHITECTURE.md, under Application emails, describes both."
		]
	},
	ProposalCreatedEditors: {
		subject: 'Proposal created for your academic venue',
		paragraphs: [
			'A proposal was created for your academic venue "$1" to help make its peer review more sustainable:',
			'<rr-button href="{origin}/venues/proposal/$2">See the proposal</rr-button>',
			"Learn more about Reciprocal Reviews to see if it's a good fit for your academic community.",
			'<rr-button href="{origin}">Learn about Reciprocal Reviews</rr-button>'
		]
	},
	// The counterpart VenueApproved never had. A proposal emails its listed editors and its
	// supporters when it is created, and emailed nobody when it ended: the people who were
	// told a venue was being proposed for their community were left to infer from silence
	// that it had not happened. Shares VenueApproved's preference -- outcome is one
	// subscription, and being told only the good half of it is not an opt-out worth offering.
	//
	// No reason is given because the interface has no field for one; the message invites a
	// reply instead, which reaches the stewards who made the decision.
	ProposalDeclined: {
		subject: 'A venue proposal was not taken forward',
		paragraphs: [
			'The proposal to bring "$1" onto Reciprocal Reviews was reviewed and has not been taken forward, and the proposal has been closed.',
			'If you think that was a mistake, or the venue is ready now, you can reply to this message to reach the stewards, or propose it again:',
			'<rr-button href="{origin}/venues/proposal">Propose a venue</rr-button>'
		],
		silencedBy: 'VenueApproved'
	},
	AssignmentApproved: {
		subject: 'Your are assigned a submission',
		paragraphs: [
			'<a href="mailto:$2">$1</a> assigned you as $3 for this submission:',
			'<rr-button href="{origin}/venue/$4/submission/$5">Open the submission</rr-button>',
			'Complete your assignment and you will receive compensation.'
		]
	},
	AssignmentRemoved: {
		subject: 'You were removed from a submission',
		paragraphs: [
			'<a href="mailto:$2">$1</a> removed you as $3 for this submission:',
			'<rr-button href="{origin}/venue/$4/submission/$5">Open the submission</rr-button>'
		]
	},
	// $1 decliner name, $2 decliner email, $3 role, $4 submission title, $5 the reason they
	// gave, $6 venue path, $7 submission id.
	//
	// A bid sets no expectation of a reply, so leaving one unanswered is fine and sends
	// nothing. Declining one is different: it is an explicit answer to a person, so it never
	// goes out without the approver's reason, and it names the approver with a mailto, as
	// AssignmentApproved does, so the decision is accountable and the bidder can ask about it.
	// Consequential rather than optional: it is the answer to something the bidder asked for.
	//
	// $5 is the approver's own words and is escaped and defanged like every argument.
	BidDeclined: {
		subject: 'Your bid on "$4" was declined',
		paragraphs: [
			'<a href="mailto:$2">$1</a> declined your bid for the $3 role on "$4", and explained:',
			'$5',
			'<rr-button href="{origin}/venue/$6/submission/$7">Open the submission</rr-button>'
		]
	},
	RoleInvite: {
		subject: 'You were invited to a reviewing role',
		paragraphs: [
			'You have been invited to the $1 role for <a href="{origin}/venue/$2">$3</a>. You can accept or decline on your profile:',
			'<rr-button href="{origin}/scholar/$4">Accept or decline</rr-button>'
		]
	},
	// A scholar volunteered for one of a venue's open roles. Sent to the holders of the
	// venue's priority-0 role as ONE message — the first in To, the rest in Cc — carrying
	// the volunteer's verified address as its Reply-To, so a holder can hit Reply and
	// welcome them while Reply All keeps the whole group on the thread. Queued by
	// public._notify_new_volunteer, which resolves the recipients and the reply address;
	// nothing here comes from the volunteer except their name.
	//
	// $6 is the priority-0 role's OWN name. A venue calls it "Editor", "Area Chair",
	// "Associate Editor", or something else entirely, so the word is read from the row
	// rather than written into the prose. Phrased to read the same whether one person holds
	// it or several.
	//
	// The body deliberately does not say "reply to welcome them": a volunteer with no
	// verified address leaves no Reply-To to promise, and the branded footer already varies
	// on exactly that condition (emailShell.ts), so it carries the sentence instead.
	NewVolunteer: {
		subject: 'A new volunteer at $3',
		paragraphs: [
			'$1 volunteered for the $2 role at $3.',
			'Their profile — reviewing status, availability, and what else they have taken on:',
			'<rr-button href="{origin}/scholar/$4">See their profile</rr-button>',
			'<rr-button href="{origin}/venue/$5/volunteers">See all volunteers</rr-button>',
			'You and everyone else in the $6 role at $3 are copied on this message.'
		],
		optional: true,
		section: 'venues'
	},
	CompensationRequested: {
		subject: 'Compensation requested for volunteer work',
		paragraphs: [
			"A scholar requested compensation for their work on a submission. Here's the note they included:",
			'"$3"',
			"If this is a valid request, approve the assignment, evaluate their work, and if it meets your venue's standards, mark the work complete so they are compensated.",
			'<rr-button href="{origin}/venue/$1/submission/$2">Open the submission</rr-button>'
		],
		// Sent to the whole approver union -- venue admins, the submission's priority-0
		// editors, and the holder of the role's approving role -- so for most recipients it
		// is news about a group's work rather than an obligation of their own.
		optional: true,
		section: 'venues'
	},
	SubmissionCharged: {
		subject: 'A submission charge awaits your approval',
		paragraphs: [
			'You were listed as a paying author on the submission "$1" to $2, with a charge of $3 tokens.',
			'The charge is only proposed — nothing moves until you approve it, and the editor may wait for every author to pay before proceeding with review. Review and approve it here:',
			'<rr-button href="{origin}/scholar/$4">Review the charge</rr-button>'
		]
	},
	SubmissionAssignedEditor: {
		subject: 'You are editing a new submission',
		paragraphs: [
			'A new submission, "$1", arrived at $2, and you are the venue\'s editor for it.',
			'<rr-button href="{origin}/venue/$3/submission/$4">Open the submission</rr-button>',
			"You were assigned automatically because you are the venue's only editor. If someone else should handle it, you can remove yourself and assign them from the submission page."
		]
	},
	SubmissionNeedsEditor: {
		subject: 'A submission is waiting for an editor',
		paragraphs: [
			'A new submission, "$1", arrived at $2 and has no editor yet. Nobody was assigned automatically, because the venue has more than one editor — or none.',
			'<rr-button href="{origin}/venue/$3/submission/$4">Open the submission</rr-button>',
			"Whoever takes it on can claim it from that page, or from the venue's submissions list. Until someone does, nothing else in the review can proceed."
		],
		// One submission or two hundred, this is the same subscription to a reader.
		silencedBy: 'SubmissionsNeedEditors'
	},
	// One digest for everyone an import seated, whatever role the file named them in and
	// whichever of the two seating paths reached them -- so it can claim neither. It used
	// to call every recipient the venue's editor and explain that they were assigned
	// because they were its ONLY editor, which was false for anyone the file named by
	// name, and for anyone holding some other role (#181). The key is kept for the same
	// reason the prose changed: public.emails.event holds it on every row already sent,
	// and a queued row is rendered by this name at send time.
	SubmissionsAssignedEditor: {
		subject: 'You have new assignments on imported submissions',
		paragraphs: [
			'$1 submission(s) were imported into $2 and assigned to you.',
			'<rr-button href="{origin}/venue/$3/submissions">See the submissions</rr-button>',
			"You were seated either because the import file named you, or because you are the only person in one of the venue's roles. Remove yourself from anything someone else should handle."
		]
	},
	SubmissionsNeedEditors: {
		subject: 'Submissions are waiting for an editor',
		paragraphs: [
			'$1 submission(s) at $2 have no editor yet.',
			'<rr-button href="{origin}/venue/$3/submissions">See the submissions</rr-button>',
			'You can claim them from that list, or assign someone else to the editor role on each.'
		],
		// Broadcast to every editor and admin of the venue, none of whom is being asked
		// personally. The highest-volume notice the platform sends, and the reminder that
		// chases it reuses this template rather than adding a second control.
		optional: true,
		section: 'venues'
	},
	WorkCompensated: {
		subject: 'You were paid for your $1 work',
		paragraphs: [
			'The approver of your $1 assignment marked your work complete and paid you $2 tokens for it. The tokens have been transferred to your account.',
			'<rr-button href="{origin}/venue/$3/submission/$4">View the submission</rr-button>'
		]
	},
	VenueOutOfTokens: {
		subject: '$5 needs more tokens to pay its reviewers',
		paragraphs: [
			'An approver at $5 tried to pay $1 tokens for $2 work on a submission, but the venue is short $3 tokens.',
			'A proposed mint transaction sized exactly to the shortfall has been recorded so if you decide to approve it, it is a one click approval. If you approve it, then approver can retry the payment:',
			'<rr-button href="{origin}/venue/$4/transactions">Review the mint</rr-button>'
		]
	},
	// The counterpart to the two declined templates below. Approving and declining a proposed
	// transaction are the same decision with opposite outcomes, and only one of them used to
	// say so: a proposer whose transaction was declined was told, and why, while a proposer
	// whose transaction was approved found out by going to look at their balance.
	//
	// One template rather than the declined pair's two. The venue title is context a decline
	// needs -- whose venue turned this down, and who to take it up with -- while an approval's
	// link already lands on the ledger that shows it.
	TransactionApproved: {
		subject: 'Your transaction was approved',
		paragraphs: [
			'Your proposed transaction for <strong>$2</strong> $3 tokens — "$1" — was approved by <a href="mailto:$5">$4</a>.',
			'The tokens have moved.',
			'<rr-button href="$6">See the record</rr-button>'
		],
		// $6 is the whole link, built by the application from the page's own origin and the
		// transaction's ids -- see TransactionDeclinedVenue below.
		urlArgs: [6],
		optional: true,
		section: 'tokens'
	},
	TransactionDeclinedVenue: {
		subject: 'Your transaction was declined',
		paragraphs: [
			'Your proposed transaction for <strong>$2</strong> $3 tokens at <strong>$4</strong> — "$1" — was declined by <a href="mailto:$6">$5</a>.',
			'Reason given: $7',
			'<rr-button href="$8">Review the transaction</rr-button>'
		],
		// $8 is the whole link, so it must stay clickable. Without this the
		// defanging meant for caller-supplied values mangled it to `https[:]//…`
		// and these emails shipped a dead link. Safe to trust: the application
		// builds it from the page's own origin and the transaction's ids — no
		// part of it is authored by whoever proposed the transaction.
		urlArgs: [8]
	},
	TransactionDeclined: {
		subject: 'Your transaction was declined',
		paragraphs: [
			'Your proposed transaction for <strong>$2</strong> $3 tokens — "$1" — was declined by <a href="mailto:$5">$4</a>.',
			'Reason given: $6',
			'<rr-button href="$7">Review the transaction</rr-button>'
		],
		// $7 is the whole link — see TransactionDeclinedVenue above.
		urlArgs: [7]
	},
	// Author thank-you notes to reviewers (#22). These are rendered in the app
	// layer like every other template, then fanned out to recipients by the
	// queue_thanks_emails RPC (which resolves recipients server-side to preserve
	// reviewer anonymity). $-args: see each method in SupabaseCRUD.
	ThanksPendingReview: {
		subject: 'A thank-you note awaits your review',
		paragraphs: [
			'An author submitted a thank-you note to share with the reviewers of a submission. Please review it before it is shared:',
			'<rr-button href="{origin}/venue/$1/submission/$2">Review the note</rr-button>'
		],
		// Goes to every admin and priority-0 editor of the venue; any one of them can vet it.
		optional: true,
		section: 'community'
	},
	ThanksReceived: {
		subject: 'You received thanks for your reviewing',
		paragraphs: [
			'An author of a submission you reviewed sent their thanks:',
			'"$1"',
			'Thank you for your reviewing work.',
			'<rr-button href="{origin}/venue/$2/submission/$3">View the submission</rr-button>'
		],
		// Gratitude, asking nothing. The clearest courtesy in the registry -- and the one a
		// reviewer who would rather not hear from authors most needs to be able to decline.
		optional: true,
		section: 'community'
	},
	// Sent to the AUTHOR when their note is approved. ThanksReceived above goes to the
	// reviewers, and ThanksDeclined below tells the author when the answer was no -- so before
	// this, the only outcome an author was never told about was the one they wanted.
	ThanksShared: {
		subject: 'Your thank-you note was shared',
		paragraphs: [
			'The thank-you note you wrote was reviewed and has been shared with the reviewers of your submission.',
			'<rr-button href="{origin}/venue/$1/submission/$2">See the note</rr-button>'
		],
		optional: true,
		section: 'community'
	},
	ThanksDeclined: {
		subject: 'Your thank-you note was not shared',
		paragraphs: [
			'The thank-you note you submitted for a submission was reviewed and not approved for sharing.',
			'Reason given: $1',
			'<rr-button href="{origin}/venue/$2/submission/$3">Revise the note</rr-button>'
		]
	},
	// Sent to the address being REPLACED, at the moment a new one is verified. The address
	// that stops receiving a scholar's mail is the one with no other way of finding out, and
	// an account's contact address changing without its previous owner being told is the shape
	// of a takeover going unnoticed. Consequential, and deliberately so: there is no version
	// of "notify me when my account changes hands" worth offering as a checkbox.
	//
	// Queued by public.verify_email, which is the only place that knows the old address --
	// it has been overwritten by the time anything else could look. $1 is the new address,
	// shown so the reader can say what it was changed to when they report it.
	EmailChanged: {
		subject: 'Your Reciprocal Reviews contact email was changed',
		paragraphs: [
			'The contact address for your Reciprocal Reviews account was changed to $1. Notifications will go there from now on, and this address will stop receiving them.',
			'If you made this change, there is nothing to do. If you did not, reply to this message and a steward will see it.'
		]
	},
	// ---- Submissions in motion -----------------------------------------------------------
	//
	// The platform announced a submission ARRIVING and a submission's work being PAID, and
	// nothing in between. Everything below is a thing that happens to a submission which the
	// people responsible for it could previously only discover by opening the page and
	// noticing it had changed.

	// $1 title, $2 venue title, $3 venue path, $4 submission id. Sent to the AUTHORS.
	//
	// The reviewers already heard: WorkCompensated reaches each of them as their own work is
	// completed. The authors heard nothing at all -- and DESIGN.md makes a done submission the
	// precondition for thanking its reviewers, so the thank-you feature had no trigger. An
	// author had to guess that reviewing had finished and go looking. That is what the second
	// paragraph is for.
	SubmissionDone: {
		subject: 'Reviewing is complete for "$1"',
		paragraphs: [
			'Reviewing is complete for your submission "$1" at $2.',
			'If you would like to, you can write a note of thanks to the people who reviewed it. They are anonymous to you, and the note reaches all of them.',
			'<rr-button href="{origin}/venue/$3/submission/$4">Open the submission</rr-button>'
		],
		optional: true,
		section: 'reviewing'
	},
	// $1 title, $2 who took it, $3 venue path, $4 submission id. Sent to the venue's OTHER
	// editors and admins -- the people SubmissionNeedsEditor went to. Without it the only way
	// to find out a submission had been picked up was to open it, so two editors could work
	// on claiming the same paper.
	SubmissionClaimed: {
		subject: 'A submission was taken on',
		paragraphs: [
			'$2 is now editing "$1", so it no longer needs an editor.',
			'<rr-button href="{origin}/venue/$3/submission/$4">Open the submission</rr-button>'
		],
		optional: true,
		section: 'venues'
	},
	// $1 title, $2 the role bid for, $3 venue path, $4 submission id.
	NewBid: {
		subject: 'A new bid on "$1"',
		paragraphs: [
			'Someone bid for the $2 role on "$1".',
			'You can approve or decline the bid from the submission.',
			'<rr-button href="{origin}/venue/$3/submission/$4">Open the submission</rr-button>'
		],
		optional: true,
		section: 'venues'
	},
	// $1 venue title, $2 sender name, $3 the sender's own word for their job at the venue,
	// $4 the note they wrote, $5 the role the recipient volunteers for, $6 venue path.
	//
	// The one notice RR sends that a person composes rather than an event triggers. Bidding
	// only works if volunteers come and bid, and every other template here fires on something
	// having ALREADY happened -- a bid arriving, a role changing, a payout. Nothing said "we
	// are short of bids this week and would like you to look", so a program chair's only
	// recourse was to export the volunteer list and mail it from outside RR, losing the
	// opt-out, the mail log, the delivery tracking and the data download in one step.
	//
	// $4 is the editor's own words, and it is an ARGUMENT rather than a body on purpose: the
	// subject, the attribution, the "why you got this" line and the link are all owned here
	// and rendered at send time, and escapeArg escapes it and defangs any URL scheme in it.
	// So a caller chooses what one paragraph says and nothing else -- not the subject, not the
	// recipients, not a link. That is a stricter contract than queue_thanks_emails, the only
	// other template a person writes into, which takes a fully pre-rendered subject and body.
	//
	// Reply-To is the sender's own verified address rather than stewards@, because this is a
	// person asking their community for help and a reply is the answer to it. That is the same
	// reasoning NewVolunteer uses, and the footer names whichever address a reply reaches.
	CallForBids: {
		subject: 'Bids needed for $1',
		paragraphs: [
			'$2, $3 of $1, writes:',
			'$4',
			'You are receiving this because you volunteer as $5 for $1. You can bid on the submissions that match your expertise.',
			'<rr-button href="{origin}/venue/$6/submissions">Bid on submissions</rr-button>'
		],
		// A courtesy, and on by default: it is infrequent, it comes from a venue this scholar
		// chose to volunteer for, and it is about the very work they volunteered to do. The
		// notices that ship OFF are the ones too frequent to impose; a venue asking for bids a
		// few times a cycle is not one of them.
		optional: true,
		section: 'reviewing'
	},
	// $1 a BiddingDigestPayload as JSON (see digestArg), $2 how many submissions it covers,
	// already worded ("1 submission", "12 submissions") by the producer.
	//
	// The weekly nudge that bidding otherwise lacks. CallForBids is an editor asking; this is
	// the platform noticing, once a week, that submissions in roles a scholar volunteers for
	// still need people, so a volunteer who forgot, or never knew something new arrived,
	// hears about it without anyone having to ask. Built by the `remind` cron from
	// public.bidding_digest_candidates, and never sent twice with the same list.
	BiddingDigest: {
		subject: '$2 open for bids in roles you volunteer for',
		paragraphs: [
			'These submissions still need people in roles you volunteer for. The ones missing the most people come first, and among those, the closest to the expertise you gave when you volunteered.',
			'$1',
			'You are receiving this because you volunteer for these roles and your profile says you are available to review. It comes on Mondays, and only when the list has changed since the last one.'
		],
		digestArg: 1,
		// On by default: it is the thing a volunteer signed up for, arrives at most weekly, and
		// is the whole remedy for bids that never come because nobody looked.
		optional: true,
		section: 'reviewing'
	},
	// $1 title, $2 venue path, $3 submission id.
	ConflictDeclared: {
		subject: 'A conflict was declared on "$1"',
		paragraphs: [
			'A scholar declared a conflict of interest with "$1", so they will not be assignable to it.',
			'<rr-button href="{origin}/venue/$2/submission/$3">Open the submission</rr-button>'
		],
		// Default OFF. An editor assigning a paper wants this; every other editor and admin at
		// a busy venue does not, and conflicts are declared far more often than papers are
		// claimed.
		optional: true,
		defaultOn: false,
		section: 'venues'
	},
	// $1 role name, $2 venue title, $3 venue path, $4 the scholar's own id.
	//
	// Consequential. An administrator can seat somebody in a role directly, without an
	// invitation to accept -- and that path told them nothing: NewVolunteer is suppressed for
	// it (it is the admin's own action, not news to the admins) and RoleInvite only fires when
	// there is an invitation. So a scholar acquired a venue commitment, possibly a welcome
	// grant with it, and the only way to notice was to read their own profile.
	RoleEnrolled: {
		subject: 'You were added to the $1 role at $2',
		paragraphs: [
			'An administrator of $2 added you to its $1 role. There was no invitation to accept — administrators can seat people directly in the roles they run.',
			'Your profile shows what you now hold, and you can stop volunteering for it at any time:',
			'<rr-button href="{origin}/scholar/$4">See your profile</rr-button>',
			'<rr-button href="{origin}/venue/$3">Open the venue</rr-button>'
		]
	},

	// ---- Tokens ------------------------------------------------------------------------
	//
	// Money moving was the least-notified category in the platform: every FAILURE around it
	// wrote to somebody -- a declined transaction, a venue short of tokens -- while the
	// transfers themselves happened in silence. A scholar who was given tokens found out by
	// visiting their balance and noticing it had changed.

	// $1 amount, $2 currency name, $3 who gave them, $4 the stated purpose, $5 the recipient's
	// own id. $3 is a venue's title or a scholar's name, resolved by the caller, because a
	// gift can come from either.
	TokensReceived: {
		subject: 'You received $1 $2 tokens',
		paragraphs: [
			'$3 transferred $1 $2 tokens to you.',
			'For: "$4"',
			'They are in your account now.',
			'<rr-button href="{origin}/scholar/$5">See your balance</rr-button>'
		],
		optional: true,
		section: 'tokens'
	},
	// $1 amount, $2 currency name, $3 venue title, $4 venue path.
	TokensMinted: {
		subject: 'New $2 tokens were minted',
		paragraphs: [
			'$1 new $2 tokens were minted into the reserve of $3.',
			'Minting changes the supply every balance in the currency is denominated in, so the venue and currency records are the place to see what it was for:',
			'<rr-button href="{origin}/venue/$4/transactions">See the transactions</rr-button>'
		],
		// Default OFF. Useful to a minter watching supply, and too frequent at an active venue
		// to impose on every admin who never asked to watch it.
		optional: true,
		defaultOn: false,
		section: 'tokens'
	},
	// $1 purpose, $2 amount, $3 currency name, $4 the charged scholar's own id.
	//
	// Consequential: it is a claim on your tokens. SubmissionCharged covers the submission
	// case, which is most of them; this is everything else, and before it those waited on a
	// reminder family that a venue has to opt into and can set to zero.
	TransactionProposed: {
		subject: 'A transaction awaits your approval',
		paragraphs: [
			'A transaction for <strong>$2</strong> $3 tokens — "$1" — has been proposed and is waiting for your approval.',
			'Nothing moves until you approve it.',
			'<rr-button href="{origin}/scholar/$4">Review the transaction</rr-button>'
		]
	},
	// $1 currency name, $2 currency id. Consequential: it is a privilege grant, and the same
	// argument as RoleInvite -- you are being given something to do.
	MinterAdded: {
		subject: 'You can now mint $1',
		paragraphs: [
			'You were made a minter of $1 on Reciprocal Reviews.',
			"Minters decide when new tokens enter a currency, which makes this authority over the supply that every holder's balance is denominated in. Venues short of tokens will ask you to approve a mint.",
			'<rr-button href="{origin}/currency/$2">Open the currency</rr-button>'
		]
	},
	// $1 currency name.
	MinterRemoved: {
		subject: 'You are no longer a minter of $1',
		paragraphs: [
			'You were removed as a minter of $1 on Reciprocal Reviews, so you can no longer approve mints for it.',
			'If that was not expected, you can reply to this message.'
		]
	},

	// ---- Venue governance ------------------------------------------------------------
	//
	// Things that change what somebody holds, is paid, or is responsible for. The platform
	// could do all of these silently: a role could be deleted out from under its volunteers,
	// priority-0 authority could move between roles, and somebody could be made an admin of a
	// venue, all without a word to anyone affected.

	// $1 the volunteer's name, $2 role name, $3 venue title, $4 venue path.
	//
	// Answering an invitation used to be deliberately silent, on the reasoning that the people
	// who would be told are the ones who sent it. But sending an invitation and learning
	// whether it was taken up are days apart, and DESIGN.md's own user stories name wanting to
	// "quickly get information about who agrees" as the thing an editor is doing here.
	InviteAccepted: {
		subject: '$1 accepted the $2 role at $3',
		paragraphs: [
			'$1 accepted your invitation to the $2 role at $3.',
			'<rr-button href="{origin}/venue/$4/volunteers">See all volunteers</rr-button>'
		],
		optional: true,
		section: 'venues'
	},
	InviteDeclined: {
		subject: '$1 declined the $2 role at $3',
		paragraphs: [
			'$1 declined your invitation to the $2 role at $3.',
			'<rr-button href="{origin}/venue/$4/volunteers">See all volunteers</rr-button>'
		],
		// The answer to a question is one subscription, whichever way it comes back.
		silencedBy: 'InviteAccepted'
	},
	// $1 the volunteer's name, $2 role name, $3 venue title, $4 venue path.
	VolunteerPaused: {
		subject: '$1 paused volunteering at $3',
		paragraphs: [
			'$1 is no longer available for the $2 role at $3, so they will not appear as assignable.',
			'<rr-button href="{origin}/venue/$4/volunteers">See all volunteers</rr-button>'
		],
		// Default OFF. Real capacity news for whoever is assigning papers this week, and too
		// frequent at a venue with many volunteers to impose on everybody who runs it.
		optional: true,
		defaultOn: false,
		section: 'venues'
	},
	VolunteerResumed: {
		subject: '$1 resumed volunteering at $3',
		paragraphs: [
			'$1 is available again for the $2 role at $3.',
			'<rr-button href="{origin}/venue/$4/volunteers">See all volunteers</rr-button>'
		],
		silencedBy: 'VolunteerPaused'
	},
	// $1 venue title, $2 venue path, $3 the message the venue is displaying.
	VenueDeactivated: {
		subject: '$1 is no longer active',
		paragraphs: [
			'$1 has been switched off on Reciprocal Reviews. It is not accepting submissions, and this is the message it is showing:',
			'"$3"',
			'<rr-button href="{origin}/venue/$2">Open the venue</rr-button>'
		],
		optional: true,
		section: 'venues'
	},
	VenueReactivated: {
		subject: '$1 is active again',
		paragraphs: [
			'$1 is live again on Reciprocal Reviews and is accepting submissions.',
			'<rr-button href="{origin}/venue/$2">Open the venue</rr-button>'
		],
		// VenueApproved fires when a steward approves a proposal, which DESIGN.md is explicit
		// is NOT the moment a venue launches. This is that moment, and it shares the
		// deactivation's control because going quiet and coming back are one subscription.
		silencedBy: 'VenueDeactivated'
	},
	// $1 role name, $2 the new amount, $3 venue title, $4 venue path.
	CompensationChanged: {
		subject: 'Compensation changed for the $1 role at $3',
		paragraphs: [
			'The compensation for the $1 role at $3 is now $2 tokens per submission.',
			'This applies to work compensated from now on.',
			'<rr-button href="{origin}/venue/$4">See roles and rates</rr-button>'
		],
		optional: true,
		section: 'venues'
	},
	// $1 venue title, $2 venue path. Consequential: administering a venue is authority over
	// its roles, its submissions and its money.
	VenueAdminAdded: {
		subject: 'You are now an administrator of $1',
		paragraphs: [
			"You were made an administrator of $1 on Reciprocal Reviews. Administrators configure a venue's roles and compensation, approve its transactions, and can assign anyone to any submission.",
			'<rr-button href="{origin}/venue/$2">Open the venue</rr-button>'
		]
	},
	VenueAdminRemoved: {
		subject: 'You are no longer an administrator of $1',
		paragraphs: [
			'You were removed as an administrator of $1 on Reciprocal Reviews.',
			'If that was not expected, you can reply to this message.'
		]
	},
	// $1 role name, $2 venue title, $3 venue path. Consequential: the role is gone and every
	// volunteer record in it went with it, which no amount of visiting the page would have
	// explained after the fact.
	RoleDeleted: {
		subject: 'The $1 role at $2 was deleted',
		paragraphs: [
			'The $1 role at $2 was deleted, and the volunteer records in it went with it. You are no longer volunteering for it.',
			'<rr-button href="{origin}/venue/$3">See the remaining roles</rr-button>'
		]
	},
	// $1 role name, $2 venue title, $3 venue path. Consequential: at priority 0 a role carries
	// the venue's editorial authority, so this hands it over or takes it away.
	RolePriorityChanged: {
		subject: 'The $1 role at $2 is now its top role',
		paragraphs: [
			"The $1 role at $2 is now the venue's top-priority role. Its holders are the venue's editors: new submissions are assigned to them, they approve assignments, and they mark submissions done.",
			'<rr-button href="{origin}/venue/$3">Open the venue</rr-button>'
		]
	},
	// $1 venue title, $2 the new path, $3 the old one. Consequential: every link anyone has
	// already pasted into a reviewing platform stops working the moment this changes, and the
	// people who pasted them are exactly these recipients.
	VenueAddressChanged: {
		subject: 'The web address of $1 changed',
		paragraphs: [
			'The Reciprocal Reviews address of $1 changed from /venue/$3 to /venue/$2.',
			"Any links you have already put into your reviewing platform's email templates point at the old address and will no longer resolve. The transaction templates on the venue page carry the new ones:",
			'<rr-button href="{origin}/venue/$2">Open the venue</rr-button>'
		]
	},

	// ---- Proposals, stewardship and the account ----------------------------------------

	// $1 venue title, $2 supporter's name, $3 proposal id.
	ProposalSupported: {
		subject: 'Someone supported your proposal for $1',
		paragraphs: [
			'$2 added their support to your proposal to bring $1 onto Reciprocal Reviews. Stewards weigh community support when deciding on a proposal.',
			'<rr-button href="{origin}/venues/proposal/$3">See the proposal</rr-button>'
		],
		optional: true,
		section: 'community'
	},
	// Consequential: stewardship is authority over the whole platform, not one venue.
	StewardAppointed: {
		subject: 'You are now a Reciprocal Reviews steward',
		paragraphs: [
			"You were made a steward of Reciprocal Reviews. Stewards approve and decline venue proposals, appoint other stewards, and receive the platform's integrity alerts.",
			'<rr-button href="{origin}/about">Read about stewards</rr-button>'
		]
	},
	StewardRemoved: {
		subject: 'You are no longer a Reciprocal Reviews steward',
		paragraphs: [
			'You were removed as a steward of Reciprocal Reviews.',
			'If that was not expected, you can reply to this message.'
		]
	},

	// ---- The scheduled reminders (supabase/functions/remind) --------------------------
	//
	// These bodies used to be written inline in the cron and POSTed straight to Resend, which
	// meant they were the one family of mail nobody could switch off, that never appeared in
	// public.emails, that got no delivery reconciliation, and that was missing from the data
	// export DESIGN.md promises counts every message a scholar was sent. Moving them here
	// fixes all four at once, because all four are consequences of going through the table.
	//
	// Two of them deliberately reuse a preference rather than owning one: chasing a thing is
	// the same subscription as being told about it, and offering "tell me about submissions
	// needing an editor" and "remind me about submissions needing an editor" as separate
	// checkboxes would be a worse settings page, not a more capable one.

	// $1 is the scholar's own last status, $2 their id. Sent at most monthly, and only to
	// someone whose status has gone stale -- see getStaleStatusReminder.
	AvailabilityReminder: {
		subject: 'Update your status',
		paragraphs: [
			"This is a friendly reminder to update your reviewing status on Reciprocal Reviews. Here's the last thing you wrote:",
			'"$1"',
			'<rr-button href="{origin}/scholar/$2">Update your status</rr-button>'
		],
		// The purest courtesy the platform sends: a periodic nudge about a field nobody is
		// waiting on. It was also, before this, the only mail with no venue-level cadence to
		// turn down and no preference to switch off.
		optional: true,
		section: 'reviewing'
	},
	// $1 is a count, $2 the recipient's own id.
	TransactionsPending: {
		subject: 'Approve proposed transactions',
		paragraphs: [
			'You have $1 proposed transaction(s) that require your approval.',
			'<rr-button href="{origin}/scholar/$2">Review transactions</rr-button>'
		],
		// Goes to a venue's admins and its currency's minters together, so for any one of them
		// it is the group's queue rather than a personal obligation.
		optional: true,
		section: 'tokens'
	},
	// $1 is a count, $2 the charged scholar's own id.
	SubmissionChargeReminder: {
		subject: 'Approve your submission charge',
		paragraphs: [
			"You have $1 proposed charge(s) awaiting your approval — typically your share of a submission's cost. The submission may not proceed to review until every author has paid.",
			'<rr-button href="{origin}/scholar/$2">Review charges</rr-button>'
		]
		// Consequential, like the SubmissionCharged notice it chases. Nobody opts out of being
		// told they owe money, and this is the reminder that exists precisely because the
		// first notice can be missed.
	},
	// $1 is a count, $2 the venue's title, $3 its path.
	CompensationPending: {
		subject: 'Compensation requests await your approval',
		paragraphs: [
			'$1 submission(s) at $2 have completed work whose compensation is awaiting your approval.',
			'<rr-button href="{origin}/venue/$3/submissions">See the submissions</rr-button>'
		],
		// The same news as CompensationRequested, arriving later. One control governs both.
		silencedBy: 'CompensationRequested'
	},
	// $1 is a count, $2 the venue's title, $3 its path.
	SubmissionsReady: {
		subject: 'Submissions may be ready to mark done',
		paragraphs: [
			'$1 submission(s) at $2 have all of their reviewing work compensated and may be ready to be marked done, which also settles editor compensation.',
			'<rr-button href="{origin}/venue/$3/submissions">See the submissions</rr-button>'
		],
		optional: true,
		section: 'venues'
	},

	// Contact-email ownership verification (#27). Sent through the normal branded pipeline
	// directly to the (still unverified) candidate address — the one message we're allowed
	// to send to an unverified email. $1 is the verification URL.
	//
	// The 24 hours below restates public.email_verifications.expires_at, which is the source
	// of truth for it. Prose cannot read a column default, so the number lives in both places
	// on purpose; src/email/templates.unit.ts asserts this half.
	VerifyEmail: {
		subject: 'Verify your Reciprocal Reviews contact email',
		paragraphs: [
			'Confirm this address to receive Reciprocal Reviews notifications. This link expires in 24 hours:',
			'<rr-button href="$1">Verify your email</rr-button>',
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
 * Every `silencedBy` names a real template. Purely a compile-time check -- see the note on
 * `Email.silencedBy` for why the field itself cannot carry this type. A unit test makes the
 * stronger assertion this cannot express: that the target is itself `optional`.
 */
type AssertSilencedBy = {
	[K in EmailType]: (typeof Emails)[K] extends { silencedBy: infer S }
		? S extends EmailType
			? K
			: never
		: K;
}[EmailType];
// Fails to compile if any `silencedBy` is not an EmailType.
const _assertSilencedBy: AssertSilencedBy = 'VerifyEmail';
void _assertSilencedBy;

/**
 * The subset of templates a scholar may silence — the keys marked `optional` above, derived
 * rather than restated so the two cannot drift. These are the values
 * `public.notification_settings.event` is meant to hold, and the settings interface is
 * generated from them, so a new preference is one flag plus one locale string.
 */
export type OptionalEmailType = {
	[K in EmailType]: (typeof Emails)[K] extends { optional: true } ? K : never;
}[EmailType];

/** The `optional` keys as a value, for rendering one control per silenceable notice. */
export const OptionalEmails = (Object.keys(Emails) as EmailType[]).filter(
	(key) => 'optional' in Emails[key]
) as OptionalEmailType[];

/**
 * The preference key governing a template, or undefined if the template is consequential and
 * cannot be silenced.
 *
 * This is the function the whole registry exists to answer, and the reason the `optional` mark
 * is worth anything: every producer used to be responsible for consulting
 * `public.notification_settings` itself (and exactly one of them ever did). The SQL seeds
 * below are generated from this, so the database answers it the same way.
 */
export function preferenceFor(event: EmailType): OptionalEmailType | undefined {
	const email = Emails[event] as Email;
	if (email.silencedBy) return preferenceFor(email.silencedBy as EmailType);
	return 'optional' in email ? (event as OptionalEmailType) : undefined;
}

/** Whether a preference is on for a scholar who has never expressed an opinion about it. */
export function defaultFor(preference: OptionalEmailType): boolean {
	return (Emails[preference] as Email).defaultOn !== false;
}

/**
 * Every silenceable template paired with the preference that governs it -- the exact contents
 * of `public.optional_emails`. Exported so a unit test can assert the seeded table matches,
 * because the database reading a stale copy of this map would silently send mail a scholar
 * turned off.
 */
export const EmailPreferences: { event: EmailType; preference: OptionalEmailType }[] = (
	Object.keys(Emails) as EmailType[]
)
	.map((event) => ({ event, preference: preferenceFor(event) }))
	.filter((row): row is { event: EmailType; preference: OptionalEmailType } => !!row.preference);

/**
 * The controls to render, grouped and ordered for the profile. Derived rather than listed, so
 * a template marked `optional` appears without anyone editing a second place.
 */
export const NotificationPreferences = NotificationSectionKeys.map((section) => ({
	section,
	preferences: OptionalEmails.filter((key) => (Emails[key] as Email).section === section)
}));

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

/**
 * The digest list a BiddingDigest carries: exactly what public.bidding_digest_candidates returns
 * in its `digest` column, already ranked and capped (supabase/schemas/bidding_digests.sql).
 */
export type BiddingDigestPayload = {
	groups: {
		venue: string;
		path: string;
		role: string;
		items: { title: string; matches: string[] }[];
		more: number;
	}[];
};

/** A slug or a uuid -- what `coalesce(slug, id::text)` can produce, and nothing that could
 * climb out of the path it is placed in. */
const VENUE_PATH = /^[a-z0-9-]+$/;

function isCount(value: unknown): value is number {
	return typeof value === 'number' && Number.isInteger(value) && value >= 0;
}

/**
 * Render a digest payload as body text: one block per venue and role, one line per submission,
 * and the link to bid. Throws on anything malformed, so a bad payload fails delivery visibly
 * (the `resend` function answers 400 and the row is marked failed) instead of mailing
 * something half-rendered.
 *
 * Every string in the payload came from a scholar -- venue and role names, titles, expertise
 * keywords -- so each is escaped and defanged exactly as an ordinary argument would be. Only
 * the link is built here, from the origin and a path checked against VENUE_PATH.
 */
export function formatBiddingDigest(json: string, base: string): string {
	const payload = JSON.parse(json) as BiddingDigestPayload;
	const text = (value: unknown) => {
		if (typeof value !== 'string') throw new Error('BiddingDigest: expected a string');
		return defangURLs(escapeArg(value));
	};
	if (!payload || !Array.isArray(payload.groups) || payload.groups.length === 0)
		throw new Error('BiddingDigest: no groups');

	return payload.groups
		.map((group) => {
			if (typeof group.path !== 'string' || !VENUE_PATH.test(group.path))
				throw new Error('BiddingDigest: bad venue path');
			if (!isCount(group.more) || !Array.isArray(group.items))
				throw new Error('BiddingDigest: bad group');
			const lines = group.items.map((item) => {
				if (!Array.isArray(item.matches)) throw new Error('BiddingDigest: bad item');
				// A title is one line whatever its author typed, or it would split the list.
				const title =
					item.title === '' ? 'Untitled submission' : text(item.title.replace(/\s+/g, ' '));
				const matches =
					item.matches.length > 0 ? ` (matches ${item.matches.map(text).join(', ')})` : '';
				return `• ${title}${matches}`;
			});
			// Blocks, not lines: the shell renders the bullets as a real list and the link as a
			// button (see paragraphsToHtml), so the call to action stays visible below a long list.
			// A venue's title and a role's name can both be blank (each defaults to ''), which
			// would leave "Bid at" pointing at nothing, so each falls back to plain words.
			const venue =
				typeof group.venue === 'string' && group.venue.trim() !== ''
					? text(group.venue.trim())
					: 'this venue';
			const role =
				typeof group.role === 'string' && group.role.trim() !== ''
					? ` · ${text(group.role.trim())}`
					: '';
			return [
				`<strong>${venue}</strong>${role}`,
				lines.join('\n'),
				...(group.more > 0 ? [`…and ${group.more} more on the bidding page.`] : []),
				`<rr-button href="${base}/venue/${group.path}/submissions">Bid at ${venue}</rr-button>`
			].join('\n\n');
		})
		.join('\n\n');
}

/**
 * Where a recipient of this event can turn it off, or undefined when they can't: the event is
 * consequential, or the mail has no scholar to point at (a steward notice, a proposal's editors).
 *
 * Goes through /login with a return path, because the controls only render on the scholar's
 * own profile while signed in, and mail is often read where the reader isn't. The anchor is the
 * section of the GOVERNING preference, so a template silenced by another lands on the control
 * that actually silences it.
 */
export function settingsUrlFor(
	event: string,
	scholar: string | null | undefined,
	origin: string = DEFAULT_ORIGIN
): string | undefined {
	if (!scholar || !(event in Emails)) return undefined;
	const preference = preferenceFor(event as EmailType);
	if (!preference) return undefined;
	const section = (Emails[preference] as Email).section;
	const base = (origin || DEFAULT_ORIGIN).replace(/\/+$/, '');
	return signInUrl(base, `/scholar/${encodeURIComponent(scholar)}#notifications-${section}`);
}

/** A link that signs the reader in, if they aren't already, and then takes them to `next` -- a
 * path on this site. The login page sends a reader who is already signed in straight on. */
export function signInUrl(base: string, next: string): string {
	return `${base}/login?next=${encodeURIComponent(next)}`;
}

/**
 * Paths a reader can use without signing in, so a button to one is left as it is. Mirrors the
 * public prefixes in src/lib/auth/requiresAuth.ts, which an edge function cannot import; a unit
 * test holds the two together. `/verify` matters most: the email-verification link has to work
 * from a signed-out inbox.
 */
export const PUBLIC_PATHS = [
	'/login',
	'/about',
	'/help',
	'/contact',
	'/brand',
	'/terms',
	'/updates',
	'/verify'
];

/**
 * Send every button that leads into the application through sign-in (#191). Nearly every page
 * an email points at -- a submission, a venue's transactions, the reader's own profile with the
 * invitation to accept on it -- shows nothing useful to someone signed out, and mail is often
 * read where the reader isn't signed in: the button looked broken. Done here, over the rendered
 * message, rather than in each template, so a new template cannot forget it; the digest's buttons
 * are built at send time and pass through here too.
 */
function throughSignIn(message: string, base: string): string {
	return message.replace(/<rr-button href="([^"]*)">/g, (button, href: string) => {
		if (!href.startsWith(`${base}/`)) return button;
		const path = href.slice(base.length);
		const bare = path.replace(/[?#].*$/, '');
		if (PUBLIC_PATHS.some((prefix) => bare === prefix || bare.startsWith(`${prefix}/`)))
			return button;
		return `<rr-button href="${signInUrl(base, path)}">`;
	});
}

/** Where the application lives, when the caller doesn't say. Production, so a
 * project that never configured the `site_url` vault secret keeps sending the
 * links it always sent. */
export const DEFAULT_ORIGIN = 'https://reciprocal.reviews';

export function renderEmail(
	template: EmailType,
	args: string[],
	origin: string = DEFAULT_ORIGIN
): { subject: string; message: string } {
	// Get the email template.
	const email = Emails[template];
	const urlArgs = new Set<number>((email as Email).urlArgs ?? []);
	const digestArg = (email as Email).digestArg;

	// The origin is substituted into the template text, NOT passed through the
	// argument path: every argument has its URL scheme defanged unless the
	// template declares that position trusted, so an origin arriving as an
	// argument would render as `https[:]//…` and the links would all be dead.
	// It comes from the database (the `site_url` vault secret), never from a
	// caller, which is what makes putting it directly into the prose safe.
	const base = (origin || DEFAULT_ORIGIN).replace(/\/+$/, '');

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
	// Resolve {origin} in the template BEFORE arguments are substituted, so an
	// argument value that happens to contain the literal text isn't expanded.
	const subject = substitute(email.subject.replaceAll('{origin}', base), (value) => value);
	const message = throughSignIn(
		substitute(email.paragraphs.join('\n\n').replaceAll('{origin}', base), (value, position) =>
			position === digestArg
				? formatBiddingDigest(value, base)
				: urlArgs.has(position)
					? escapeArg(value)
					: defangURLs(escapeArg(value))
		),
		base
	);

	// The "automated email" footer is added by the branded shell at send time
	// (supabase/functions/_shared/emailShell.ts), so it isn't appended here.

	return { subject, message };
}
