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
			'{origin}/venue/$2',
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
			'{origin}/venues/proposal/$2',
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
	ProposalCreatedEditors: {
		subject: 'Proposal created for your academic venue',
		paragraphs: [
			'A proposal was created for your academic venue "$1" to help make its peer review more sustainable:',
			'{origin}/venues/proposal/$2',
			"Learn more about Reciprocal Reviews to see if it's a good fit for your academic community.",
			'{origin}'
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
			'{origin}/venues/proposal'
		],
		silencedBy: 'VenueApproved'
	},
	AssignmentApproved: {
		subject: 'Your are assigned a submission',
		paragraphs: [
			'<a href="mailto:$2">$1</a> assigned you as $3 for this submission:',
			'{origin}/venue/$4/submission/$5',
			'Complete your assignment and you will receive compensation.'
		]
	},
	AssignmentRemoved: {
		subject: 'You were removed from a submission',
		paragraphs: [
			'<a href="mailto:$2">$1</a> removed you as $3 for this submission:',
			'{origin}/venue/$4/submission/$5'
		]
	},
	RoleInvite: {
		subject: 'You were invited to a reviewing role',
		paragraphs: [
			'You have been invited to the $1 role for <a href="{origin}/venue/$2">$3</a>. You can accept or decline on your profile:',
			'{origin}/scholar/$4'
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
			'{origin}/scholar/$4',
			'Everyone volunteering at the venue:',
			'{origin}/venue/$5/volunteers',
			'You and everyone else in the $6 role at $3 are copied on this message.'
		],
		optional: true,
		section: 'venues'
	},
	CompensationRequested: {
		subject: 'Compensation requested for volunteer work',
		paragraphs: [
			"A scholar requested compensation for <a href='{origin}/venue/$1/submission/$2'>this submission</a>. Here's the note they included:",
			'"$3"',
			"If this is a valid request, approve the assignment, evaluate their work, and if it meets your venue's standards, mark the work complete so they are compensated."
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
			'{origin}/scholar/$4'
		]
	},
	SubmissionAssignedEditor: {
		subject: 'You are editing a new submission',
		paragraphs: [
			'A new submission, "$1", arrived at $2, and you are the venue\'s editor for it.',
			'{origin}/venue/$3/submission/$4',
			"You were assigned automatically because you are the venue's only editor. If someone else should handle it, you can remove yourself and assign them from the submission page."
		]
	},
	SubmissionNeedsEditor: {
		subject: 'A submission is waiting for an editor',
		paragraphs: [
			'A new submission, "$1", arrived at $2 and has no editor yet. Nobody was assigned automatically, because the venue has more than one editor — or none.',
			'{origin}/venue/$3/submission/$4',
			"Whoever takes it on can claim it from that page, or from the venue's submissions list. Until someone does, nothing else in the review can proceed."
		],
		// One submission or two hundred, this is the same subscription to a reader.
		silencedBy: 'SubmissionsNeedEditors'
	},
	SubmissionsAssignedEditor: {
		subject: 'You are editing newly imported submissions',
		paragraphs: [
			"$1 submission(s) were imported into $2, and you are the venue's editor for all of them.",
			'{origin}/venue/$3/submissions',
			"You were assigned automatically because you are the venue's only editor. Remove yourself from any that someone else should handle."
		]
	},
	SubmissionsNeedEditors: {
		subject: 'Submissions are waiting for an editor',
		paragraphs: [
			'$1 submission(s) at $2 have no editor yet.',
			'{origin}/venue/$3/submissions',
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
			'You can view the submission here: {origin}/venue/$3/submission/$4'
		]
	},
	VenueOutOfTokens: {
		subject: '$5 needs more tokens to pay its reviewers',
		paragraphs: [
			'An approver at $5 tried to pay $1 tokens for $2 work on a submission, but the venue is short $3 tokens.',
			'A proposed mint transaction sized exactly to the shortfall has been recorded so if you decide to approve it, it is a one click approval. If you approve it, then approver can retry the payment:',
			'{origin}/venue/$4/transactions'
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
			'The tokens have moved. You can see the record here: $6'
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
			'You can review and follow up on this here: $8'
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
			'You can review and follow up on this here: $7'
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
			'{origin}/venue/$1/submission/$2'
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
			'Thank you for your reviewing work. You can view the submission here:',
			'{origin}/venue/$2/submission/$3'
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
			'You can see it here:',
			'{origin}/venue/$1/submission/$2'
		],
		optional: true,
		section: 'community'
	},
	ThanksDeclined: {
		subject: 'Your thank-you note was not shared',
		paragraphs: [
			'The thank-you note you submitted for a submission was reviewed and not approved for sharing.',
			'Reason given: $1',
			'You can review and revise it here:',
			'{origin}/venue/$2/submission/$3'
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
			'You can see it here, and if you would like to, write a note of thanks to the people who reviewed it — they are anonymous to you, and the note reaches all of them:',
			'{origin}/venue/$3/submission/$4'
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
			'{origin}/venue/$3/submission/$4'
		],
		optional: true,
		section: 'venues'
	},
	// $1 title, $2 the role bid for, $3 venue path, $4 submission id.
	NewBid: {
		subject: 'A new bid on "$1"',
		paragraphs: [
			'Someone bid for the $2 role on "$1".',
			'You can approve or decline the bid from the submission:',
			'{origin}/venue/$3/submission/$4'
		],
		optional: true,
		section: 'venues'
	},
	// $1 title, $2 venue path, $3 submission id.
	ConflictDeclared: {
		subject: 'A conflict was declared on "$1"',
		paragraphs: [
			'A scholar declared a conflict of interest with "$1", so they will not be assignable to it.',
			'{origin}/venue/$2/submission/$3'
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
			'{origin}/scholar/$4',
			'The venue is here: {origin}/venue/$3'
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
			'They are in your account now: {origin}/scholar/$5'
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
			'{origin}/venue/$4/transactions'
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
			'Nothing moves until you approve it. You can review it here:',
			'{origin}/scholar/$4'
		]
	},
	// $1 currency name, $2 currency id. Consequential: it is a privilege grant, and the same
	// argument as RoleInvite -- you are being given something to do.
	MinterAdded: {
		subject: 'You can now mint $1',
		paragraphs: [
			'You were made a minter of $1 on Reciprocal Reviews.',
			"Minters decide when new tokens enter a currency, which makes this authority over the supply that every holder's balance is denominated in. Venues short of tokens will ask you to approve a mint.",
			'{origin}/currency/$2'
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
			'Everyone volunteering at the venue: {origin}/venue/$4/volunteers'
		],
		optional: true,
		section: 'venues'
	},
	InviteDeclined: {
		subject: '$1 declined the $2 role at $3',
		paragraphs: [
			'$1 declined your invitation to the $2 role at $3.',
			'Everyone volunteering at the venue: {origin}/venue/$4/volunteers'
		],
		// The answer to a question is one subscription, whichever way it comes back.
		silencedBy: 'InviteAccepted'
	},
	// $1 the volunteer's name, $2 role name, $3 venue title, $4 venue path.
	VolunteerPaused: {
		subject: '$1 paused volunteering at $3',
		paragraphs: [
			'$1 is no longer available for the $2 role at $3, so they will not appear as assignable.',
			'{origin}/venue/$4/volunteers'
		],
		// Default OFF. Real capacity news for whoever is assigning papers this week, and too
		// frequent at a venue with many volunteers to impose on everybody who runs it.
		optional: true,
		defaultOn: false,
		section: 'venues'
	},
	VolunteerResumed: {
		subject: '$1 resumed volunteering at $3',
		paragraphs: ['$1 is available again for the $2 role at $3.', '{origin}/venue/$4/volunteers'],
		silencedBy: 'VolunteerPaused'
	},
	// $1 venue title, $2 venue path, $3 the message the venue is displaying.
	VenueDeactivated: {
		subject: '$1 is no longer active',
		paragraphs: [
			'$1 has been switched off on Reciprocal Reviews. It is not accepting submissions, and this is the message it is showing:',
			'"$3"',
			'{origin}/venue/$2'
		],
		optional: true,
		section: 'venues'
	},
	VenueReactivated: {
		subject: '$1 is active again',
		paragraphs: [
			'$1 is live again on Reciprocal Reviews and is accepting submissions.',
			'{origin}/venue/$2'
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
			"This applies to work compensated from now on. The venue's roles and rates: {origin}/venue/$4"
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
			'{origin}/venue/$2'
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
			"The venue's remaining roles: {origin}/venue/$3"
		]
	},
	// $1 role name, $2 venue title, $3 venue path. Consequential: at priority 0 a role carries
	// the venue's editorial authority, so this hands it over or takes it away.
	RolePriorityChanged: {
		subject: 'The $1 role at $2 is now its top role',
		paragraphs: [
			"The $1 role at $2 is now the venue's top-priority role. Its holders are the venue's editors: new submissions are assigned to them, they approve assignments, and they mark submissions done.",
			'{origin}/venue/$3'
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
			'{origin}/venue/$2'
		]
	},

	// ---- Proposals, stewardship and the account ----------------------------------------

	// $1 venue title, $2 supporter's name, $3 proposal id.
	ProposalSupported: {
		subject: 'Someone supported your proposal for $1',
		paragraphs: [
			'$2 added their support to your proposal to bring $1 onto Reciprocal Reviews. Stewards weigh community support when deciding on a proposal.',
			'{origin}/venues/proposal/$3'
		],
		optional: true,
		section: 'community'
	},
	// Consequential: stewardship is authority over the whole platform, not one venue.
	StewardAppointed: {
		subject: 'You are now a Reciprocal Reviews steward',
		paragraphs: [
			"You were made a steward of Reciprocal Reviews. Stewards approve and decline venue proposals, appoint other stewards, and receive the platform's integrity alerts.",
			'{origin}/about'
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
			'You can update it here: {origin}/scholar/$2'
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
			'Please review and approve them here: {origin}/scholar/$2'
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
			'Review and approve here: {origin}/scholar/$2'
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
			'{origin}/venue/$3/submissions'
		],
		// The same news as CompensationRequested, arriving later. One control governs both.
		silencedBy: 'CompensationRequested'
	},
	// $1 is a count, $2 the venue's title, $3 its path.
	SubmissionsReady: {
		subject: 'Submissions may be ready to mark done',
		paragraphs: [
			'$1 submission(s) at $2 have all of their reviewing work compensated and may be ready to be marked done, which also settles editor compensation.',
			'{origin}/venue/$3/submissions'
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
	const message = substitute(
		email.paragraphs.join('\n\n').replaceAll('{origin}', base),
		(value, position) => (urlArgs.has(position) ? escapeArg(value) : defangURLs(escapeArg(value)))
	);

	// The "automated email" footer is added by the branded shell at send time
	// (supabase/functions/_shared/emailShell.ts), so it isn't appended here.

	return { subject, message };
}
