// Where people can reach Reciprocal Reviews, and each other.
//
// One module so the front door is defined once: the footer, /contact, the beta
// banner, and /updates all point at the same places, and moving one of them is a
// single edit rather than a search across routes.

// Re-exported rather than redeclared: this is the same address every email we send
// carries as its Reply-To, and two copies of it could drift apart silently — the
// interface would advertise a mailbox nobody was reading.
export { SUPPORT_EMAIL } from '../email/emailShell';

/** Community questions and ideas. Threaded and searchable, unlike chat. */
export const DISCUSSIONS_URL = 'https://github.com/reciprocalreviews/reciprocalapp/discussions';

/** Defects and feature requests — for people who are comfortable here. Everyone
 * else should use the steward inbox, which is why this is no longer the footer's
 * only outbound link. */
export const ISSUES_URL = 'https://github.com/reciprocalreviews/reciprocalapp/issues';

/** The newsletter: where the project is going, as opposed to /updates, which is
 * what changed in the last release. */
export const NEWSLETTER_URL = 'https://reciprocalreviews.substack.com';
