import { describe, expect, it } from 'vitest';
import {
	Emails,
	NotificationSectionKeys,
	OptionalEmails,
	preferenceFor,
	renderEmail,
	type Email,
	type EmailType
} from './templates';
import { readFileSync } from 'node:fs';
import { seedSQL } from './notificationSeeds';
import en from '../../static/locales/en.json';

describe('renderEmail', () => {
	it('escapes markup in argument values', () => {
		const { message } = renderEmail('VenueApproved', ['<script>alert(1)</script>', 'venue-id']);
		expect(message).not.toContain('<script>');
		expect(message).toContain('&lt;script&gt;');
	});

	it('defangs URLs in untrusted arguments so they cannot be auto-linked', () => {
		// paragraphsToHtml auto-links bare `https://` text at send time, so an argument
		// carrying a URL would otherwise arrive as a real link in branded mail.
		const { message } = renderEmail('VenueApproved', ['https://example.invalid/steal', 'v']);
		expect(message).toContain('https[:]//example.invalid/steal');
		expect(message).not.toContain('https://example.invalid');
	});

	it('leaves template-owned URLs intact', () => {
		const { message } = renderEmail('VenueApproved', ['A venue', 'venue-id']);
		expect(message).toContain('https://reciprocal.reviews/venue/venue-id');
	});

	it('sends links to the origin it is given', () => {
		// Templates used to hardcode production, so mail from a local stack or
		// staging pointed at reciprocal.reviews — which made every flow that
		// arrives by email untestable anywhere but production.
		const { message } = renderEmail(
			'VenueApproved',
			['A venue', 'venue-id'],
			'http://localhost:5173'
		);
		expect(message).toContain('http://localhost:5173/venue/venue-id');
		expect(message).not.toContain('reciprocal.reviews');
	});

	it('falls back to production when no origin is given', () => {
		// An unconfigured project keeps sending the links it always sent.
		const { message } = renderEmail('VenueApproved', ['A venue', 'venue-id']);
		expect(message).toContain('https://reciprocal.reviews/venue/venue-id');
	});

	it('ignores a trailing slash on the origin', () => {
		const { message } = renderEmail(
			'VenueApproved',
			['A venue', 'venue-id'],
			'http://localhost:5173/'
		);
		expect(message).toContain('http://localhost:5173/venue/venue-id');
		expect(message).not.toContain('5173//venue');
	});

	it('does not expand {origin} appearing inside an argument value', () => {
		// The origin is resolved in the template before arguments are substituted,
		// so a venue title containing the literal token stays literal.
		const { message } = renderEmail('VenueApproved', ['{origin}', 'venue-id'], 'http://local');
		expect(message).toContain('{origin}');
	});

	it('keeps the decline link clickable', () => {
		// TransactionDeclined passes its link as an argument, and arguments are
		// defanged unless the template declares the position trusted — so these
		// emails shipped a visibly mangled, unclickable link.
		const { message } = renderEmail('TransactionDeclined', [
			'purpose',
			'3',
			'Tokens',
			'Decliner',
			'decliner@uni.edu',
			'reason',
			'https://reciprocal.reviews/scholar/abc/transactions'
		]);
		expect(message).toContain('https://reciprocal.reviews/scholar/abc/transactions');
		expect(message).not.toContain('[:]');
	});

	it('keeps a declared URL argument clickable', () => {
		// VerifyEmail declares urlArgs: [1] — the link is built server-side, not by a caller.
		const { message } = renderEmail('VerifyEmail', ['https://reciprocal.reviews/verify/abc123']);
		expect(message).toContain('https://reciprocal.reviews/verify/abc123');
		expect(message).not.toContain('[:]');
	});

	// The lifetime is decided by public.email_verifications.expires_at, but prose cannot read
	// a column default, so the number is stated in this template too. This is the assertion
	// that keeps the two from drifting into telling a scholar the wrong deadline — the SQL
	// half is pinned by supabase/tests/rls/email_verifications_rls.sql.
	it('tells the recipient how long the verification link lasts', () => {
		const { message } = renderEmail('VerifyEmail', ['https://reciprocal.reviews/verify/abc123']);
		expect(message).toContain('24 hours');
	});

	it('substitutes every occurrence of a placeholder, not just the first', () => {
		const { message } = renderEmail('RoleInvite', ['Reviewer', 'venue-id', 'Venue', 'scholar-id']);
		// $2 appears once and $4 once, but $1/$3 are what we can see repeated in prose;
		// assert no unsubstituted placeholder survives anywhere.
		expect(message).not.toMatch(/\$\d/);
	});

	it('leaves an unknown placeholder as written rather than rendering undefined', () => {
		const { message } = renderEmail('VenueApproved', ['Only one arg']);
		expect(message).not.toContain('undefined');
		expect(message).toContain('$2');
	});
});

describe('NewVolunteer', () => {
	const args = ['Ada Lovelace', 'Reviewer', 'TOCE', 'scholar-id', 'venue-id', 'Area Chair'];

	// The priority-0 role is called whatever the venue calls it — "Editor", "Area Chair",
	// "Associate Editor". Writing a word into the prose would be wrong for most venues, so
	// the name is an argument resolved from the row.
	it("names the venue's own word for its top role", () => {
		const { message } = renderEmail('NewVolunteer', args);
		expect(message).toContain('Area Chair');
		expect(message).not.toContain('Editor');
	});

	it('names the volunteer, the role they took, and the venue', () => {
		const { subject, message } = renderEmail('NewVolunteer', args);
		expect(subject).toContain('TOCE');
		expect(message).toContain('Ada Lovelace');
		expect(message).toContain('Reviewer');
	});

	it('links to the volunteer and to the venue roster', () => {
		const { message } = renderEmail('NewVolunteer', args, 'http://localhost:5173');
		expect(message).toContain('http://localhost:5173/scholar/scholar-id');
		expect(message).toContain('http://localhost:5173/venue/venue-id/volunteers');
	});

	// The name is the one value here a scholar chooses, and it lands in genuinely branded
	// mail from notifications@reciprocal.reviews. A live link in it would be phishing.
	it("defangs a link hiding in the volunteer's name", () => {
		const { message } = renderEmail('NewVolunteer', ['https://evil.example', ...args.slice(1)]);
		expect(message).toContain('https[:]//evil.example');
		expect(message).not.toContain('https://evil.example');
	});

	it('substitutes every placeholder', () => {
		const { subject, message } = renderEmail('NewVolunteer', args);
		expect(subject).not.toMatch(/\$\d/);
		expect(message).not.toMatch(/\$\d/);
	});
});

describe('SubmissionsAssignedEditor', () => {
	const args = ['3', 'Transactions on Knowledge', 'knowledge'];

	// One digest goes to everyone a bulk import seated, in whatever roles the file named
	// them. It used to call all of them the venue's editor, so an associate editor was
	// told they were editing the papers they had been asked to review (#181). Same rule as
	// NewVolunteer above, reaching the opposite conclusion: there the role is data and is
	// passed in, here the digest covers several roles at once and so names none.
	it('names no role at all', () => {
		const { subject, message } = renderEmail('SubmissionsAssignedEditor', args);
		expect(`${subject} ${message}`).not.toMatch(/editor/i);
	});

	// The other half of #181. Both seating paths -- named in the file, and the fallback
	// that seats a venue's sole editor -- feed this one message, and the recipient may
	// have arrived by either or by both, so it offers them rather than asserting one.
	it('gives both reasons someone may have been seated, and claims neither', () => {
		const { message } = renderEmail('SubmissionsAssignedEditor', args);
		expect(message).toContain('named you');
		expect(message).toContain('only person');
		expect(message).not.toContain("you are the venue's only");
	});

	it('names the venue and how many submissions arrived', () => {
		const { message } = renderEmail('SubmissionsAssignedEditor', args);
		expect(message).toContain('Transactions on Knowledge');
		expect(message).toContain('3 submission(s)');
	});

	it("links to the venue's submissions list", () => {
		const { message } = renderEmail('SubmissionsAssignedEditor', args, 'http://localhost:5173');
		expect(message).toContain('http://localhost:5173/venue/knowledge/submissions');
	});

	it('defangs a link hiding in the venue title', () => {
		const { message } = renderEmail('SubmissionsAssignedEditor', [
			'3',
			'https://evil.example',
			'knowledge'
		]);
		expect(message).toContain('https[:]//evil.example');
		expect(message).not.toContain('https://evil.example');
	});

	it('substitutes every placeholder', () => {
		const { subject, message } = renderEmail('SubmissionsAssignedEditor', args);
		expect(subject).not.toMatch(/\$\d/);
		expect(message).not.toMatch(/\$\d/);
	});
});

describe('optional notices', () => {
	// The registry decides what a scholar may silence, and the settings interface is
	// generated from it. A template marked optional with no label would render a control
	// with no words on it; a label with no template would be a setting for nothing.
	it('gives every silenceable notice a label on the scholar profile', () => {
		const labels = Object.keys(en.page.scholar.notifications.label).sort();
		expect([...OptionalEmails].sort()).toEqual(labels);
	});

	// Consequential mail is not a courtesy. Someone who has been charged, declined, or
	// assigned does not get to opt out of being told.
	it('leaves consequential mail with no opt-out', () => {
		for (const event of [
			'SubmissionCharged',
			'TransactionDeclined',
			'VerifyEmail',
			'WorkCompensated'
		])
			expect(preferenceFor(event as EmailType)).toBeUndefined();
		expect(Object.keys(Emails).length).toBeGreaterThan(OptionalEmails.length);
	});

	// `silencedBy` lets a reminder share the control of the notice it chases. Pointing it at a
	// template that is not itself silenceable would produce a deferral chain ending at no key
	// at all, and `preferenceFor` would return undefined -- silently making the notice
	// consequential rather than failing. The type system checks the target EXISTS; only this
	// can check that it owns a preference.
	it('resolves every deferral to a real preference', () => {
		for (const key of Object.keys(Emails) as EmailType[]) {
			const silencedBy = (Emails[key] as Email).silencedBy;
			if (silencedBy === undefined) continue;
			expect(OptionalEmails, `${key} defers to ${silencedBy}`).toContain(silencedBy);
			expect(preferenceFor(key)).toBe(silencedBy);
		}
	});

	// A control is rendered inside its section, so one with no section is not rendered at all
	// -- a preference that exists, accepts writes, and can never be reached.
	it('puts every control in a section the profile renders', () => {
		for (const key of OptionalEmails) {
			const section = (Emails[key] as Email).section;
			expect(NotificationSectionKeys, `${key} has no section`).toContain(section);
		}
		expect(Object.keys(en.page.scholar.notifications.section).sort()).toEqual(
			[...NotificationSectionKeys].sort()
		);
	});

	// Only a template that OWNS a key can carry a default: the deferring template's own mark
	// would be read by nobody, so a `defaultOn` there is a silent no-op rather than an error.
	it('puts defaults only where they are read', () => {
		for (const key of Object.keys(Emails) as EmailType[]) {
			const email = Emails[key] as Email;
			if (email.defaultOn === undefined) continue;
			expect(email.optional, `${key} sets defaultOn without owning a key`).toBe(true);
		}
	});
});

// The database cannot read TypeScript, so public.notification_preferences and
// public.optional_emails are a generated copy of the marks above, and public.queue_email
// consults that copy rather than this file. A copy that drifts does not fail loudly: it mails
// people notices they switched off, or silences ones they did not. So the committed SQL is
// compared against freshly generated SQL here.
//
// If this fails, run `node scripts/notification-seeds.js` and paste the output over the seed
// block in supabase/schemas/notification_settings.sql -- AND put the same block in a new
// migration, since only migrations run on reset.
describe('generated SQL seed', () => {
	const expected = seedSQL();

	// The DATA is compared, not the text. The committed copy is run through Prettier's SQL
	// printer and the generator's output is not, so the two differ in line wrapping and in
	// whether `(` is padded — neither of which is what this test is about. What has to match is
	// which keys exist, what each defaults to, and which template each governs.
	const tuples = (sql: string, table: string) => {
		const start = sql.indexOf(table);
		if (start === -1) return [];
		const end = sql.indexOf(';', start);
		return [...sql.slice(start, end).matchAll(/\(\s*'(\w+)'\s*,\s*'?(\w+)'?\s*\)/g)]
			.map(([, a, b]) => `${a}=${b}`)
			.sort();
	};

	it('matches what is committed in supabase/schemas', () => {
		const schema = readFileSync('supabase/schemas/notification_settings.sql', 'utf8');
		// Anchored on the column lists, which appear only in the inserts — the table names
		// themselves also appear in the foreign keys further up the file.
		for (const table of ['(key, default_on)', '(event, preference)'])
			expect(tuples(schema, table), table).toEqual(tuples(expected, table));
		// Guard against the selector silently matching nothing and the test passing vacuously.
		expect(tuples(expected, '(key, default_on)').length).toBeGreaterThan(10);
	});

	it('has been applied by a migration', () => {
		// Not which migration -- a later one may legitimately supersede an earlier one -- only
		// that the current expectation exists somewhere in the applied history.
		const applied = readFileSync(
			'supabase/migrations/20260913200000_notification_preferences.sql',
			'utf8'
		);
		expect(applied).toContain('create table if not exists public.notification_preferences');
	});
});
