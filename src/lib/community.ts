// Where people can reach Reciprocal Reviews, and each other.
//
// One module so the front door is defined once: the footer, /contact, the beta
// banner, and /updates all point at the same places, and moving one of them is a
// single edit rather than a search across routes.

// Re-exported rather than redeclared: this is the same address every email not about a
// venue carries as its Reply-To, and two copies of it could drift apart silently — the
// interface would advertise a mailbox nobody was reading. The steward inbox is for the
// platform itself; questions about a venue go to its editors.
//
// The issues URL is re-exported for the same reason: every email footer names it too.
// Defects and feature requests go there, not to the steward inbox, where a report is one
// nobody else can see, follow, or add to.
export { ISSUES_URL, SUPPORT_EMAIL } from '../email/emailShell';

/** Community questions and ideas. Threaded and searchable, unlike chat. */
export const DISCUSSIONS_URL = 'https://github.com/reciprocalreviews/reciprocalapp/discussions';

/** The newsletter: where the project is going, as opposed to /updates, which is
 * what changed in the last release. */
export const NEWSLETTER_URL = 'https://reciprocalreviews.substack.com';
