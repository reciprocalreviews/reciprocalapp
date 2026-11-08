// Example digests for the unit tests and the email contact sheet (scripts/email-sheet.js), in
// the shape public.bidding_digest_candidates returns. Not seed data and never loaded into a
// database.

import type { BiddingDigestPayload } from './templates';

/** What bidding_digest_candidates returns for r2@uni.edu (Reese Urcher, "peer review, history
 * of science, testimony") against a freshly reset supabase/seed.sql, copied with a read-only
 * query. */
export const ReeseDigest: BiddingDigestPayload = {
	groups: [
		{
			more: 0,
			path: 'knowledge',
			role: 'Reviewer',
			items: [
				{
					title: 'A Study on the Effectiveness of Peer Review Incentives in Academic Publishing',
					matches: ['peer review']
				},
				{
					title: 'A Reverse Engineering of Authorship from Reference Counts',
					matches: []
				},
				{
					title: 'On the Impossibility of Knowing Whether a Review Was Read',
					matches: []
				},
				{
					title: 'An Argument That Peer Review Cannot Be Studied by Peer Review',
					matches: ['peer review']
				},
				{
					title: 'Who Reads the Supplementary Material?',
					matches: []
				},
				{
					title: 'Retraction Notices as a Genre',
					matches: []
				},
				{
					title: 'Sampling Frames in Studies of Scholarly Behavior',
					matches: []
				}
			],
			venue: 'ToK'
		}
	]
};

/** Two venues, one past the cap. The first venue is invented. */
export const TwoVenueDigest: BiddingDigestPayload = {
	groups: [
		{
			venue: 'Annals of Doubt',
			path: 'doubt',
			role: 'Referee',
			more: 7,
			items: [
				{
					title: 'Negative Results and the Journals That Refuse Them',
					matches: []
				},
				{
					title: 'Preregistration as Ritual',
					matches: ['research methods']
				},
				{
					title: 'Peer Review at Conference Scale',
					matches: ['peer review']
				},
				{
					title: 'On Anonymous Review in Communities of Forty People',
					matches: ['peer review']
				},
				{
					title: 'Open Review and the Chilling of Criticism',
					matches: ['peer review']
				},
				{
					title: 'Statistical Power in Studies of Statistical Power',
					matches: []
				},
				{
					title: 'The Half-Life of a Replication Crisis',
					matches: ['replication']
				}
			]
		},
		...ReeseDigest.groups
	]
};

/** Scholar-supplied strings that must render inert: markup, a live-looking link, entities. */
export const HostileDigest: BiddingDigestPayload = {
	groups: [
		{
			venue: '<b>Bold</b> & Brave',
			path: 'doubt',
			role: 'Reviewer <script>alert(1)</script>',
			more: 0,
			items: [
				{
					title: 'Click https://evil.example/login to see the "full" paper',
					matches: ['phishing', '<i>markup</i>']
				}
			]
		}
	]
};

/** How many submissions a digest covers, for its subject line. */
export function totalOf(digest: BiddingDigestPayload): number {
	return digest.groups.reduce((sum, group) => sum + group.items.length + group.more, 0);
}
