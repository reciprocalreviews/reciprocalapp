import z from 'zod';
import { requireSecretKey } from '../_shared/auth.ts';
import { corsHeaders } from '../_shared/cors.ts';
import {
	FROM_EMAIL,
	renderBrandedEmail,
	SUPPORT_EMAIL,
	type EmailVenue
} from '../_shared/emailShell.ts';
import {
	DEFAULT_ORIGIN,
	Emails,
	renderEmail,
	settingsUrlFor,
	type EmailType
} from '../_shared/templates.ts';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const isLocal = Deno.env.get('PUBLIC_SUPABASE_URL')?.includes('127.0.0.1') ?? false;

// `subject`/`message` are optional: a row queued by the database (see
// public.request_email_verification) carries an `event` and `args` instead, and is
// rendered here at send time. That is what keeps the body out of the caller's hands for
// mail whose recipient the caller chose — see supabase/functions/_shared/templates.ts.
const ResendBodySchema = z.object({
	to: z.string().email(),
	subject: z.string().nullish(),
	message: z.string().nullish(),
	event: z.string().nullish(),
	args: z.array(z.string()).nullish(),
	// The rest of the recipients, when a message is meant to be ONE shared thread rather
	// than N private copies. Like `to`, these are resolved inside the database from
	// scholars.email — the emails table's INSERT privilege is revoked from authenticated
	// and anon, so no caller can name them.
	cc: z.array(z.string().email()).nullish(),
	// Where a reply should go, when that is not the steward inbox. Same provenance as `cc`
	// and the same reason it is safe: only the database can set it. Absent means stewards@,
	// which is what every message sent before this field existed carried.
	reply_to: z.string().email().nullish(),
	// The application origin the rendered links should point at, from the
	// `site_url` vault secret via send_email(). Only the database can set it —
	// this function refuses callers without a project secret key — so it is
	// trusted enough to appear in link positions. Absent, links go to
	// production, which is what they always did.
	origin: z.string().nullish(),
	// The recipient's scholar id, when the message has one. Used only to link an optional
	// notice's footer to that scholar's notification settings.
	scholar: z.string().uuid().nullish(),
	// The venue the message is about, when it is about one: its title and the path segment
	// of its page, read by send_email() from the row's `venue`. Used only by the footer, which
	// names the venue and sends questions about it to its editors.
	venue_title: z.string().nullish(),
	venue_path: z.string().nullish()
});

export type ResendBody = z.infer<typeof ResendBodySchema>;

const handler = async (request: Request): Promise<Response> => {
	// Permit client side requests
	if (request.method === 'OPTIONS') {
		return new Response('ok', { headers: corsHeaders });
	}

	// Only the database may send mail. This function takes the recipient, and optionally
	// the template arguments, straight from its caller, so without this check anyone
	// holding a public key could send branded mail from notifications@reciprocal.reviews.
	const forbidden = await requireSecretKey(request, corsHeaders);
	if (forbidden) return forbidden;

	try {
		/** Get the message body */
		const bodyJSON = await request.json();
		// Validate the message body
		const parsed = ResendBodySchema.parse(bodyJSON);
		const { to } = parsed;
		const cc = parsed.cc ?? [];
		const replyTo = parsed.reply_to ?? undefined;
		const venue: EmailVenue | undefined =
			parsed.venue_title && parsed.venue_path
				? {
						title: parsed.venue_title,
						url: `${(parsed.origin || DEFAULT_ORIGIN).replace(/\/+$/, '')}/venue/${encodeURIComponent(parsed.venue_path)}`
					}
				: undefined;

		// Render from the template registry when the queuing code did not supply a body.
		// An unknown event is a programming error, not something to deliver blank.
		let subject = parsed.subject ?? undefined;
		let message = parsed.message ?? undefined;
		if (subject === undefined || message === undefined) {
			if (!parsed.event || !(parsed.event in Emails))
				throw new Error(`Cannot render email: unknown event ${parsed.event}`);
			const rendered = renderEmail(
				parsed.event as EmailType,
				parsed.args ?? [],
				parsed.origin ?? undefined
			);
			subject = rendered.subject;
			message = rendered.message;
		}

		// Where the recipient can turn this notice off, for one they can. Built from the event
		// and the scholar, never from the body, so pre-rendered mail gets it too.
		const settingsUrl = parsed.event
			? settingsUrlFor(parsed.event, parsed.scholar, parsed.origin ?? undefined)
			: undefined;

		let returnData;

		if (isLocal) {
			console.log('--- email sent ---');
			console.log('to: ', to);
			if (cc.length > 0) console.log('cc: ', cc.join(', '));
			console.log('reply-to:', replyTo ?? SUPPORT_EMAIL);
			if (venue) console.log('venue:', venue.title, venue.url);
			console.log('subject:', subject);
			console.log('message:', message);
			if (settingsUrl) console.log('settings:', settingsUrl);
			console.log('---');

			returnData = null;
		} else {
			// Wrap the stored plain-text body in the shared branded shell, sending
			// both an HTML version and a text/plain alternative.
			// The footer follows the header: a message with its own Reply-To says so, rather
			// than repeating the steward promise that would be false for it.
			const { html, text } = renderBrandedEmail(
				subject,
				message,
				parsed.origin ?? undefined,
				replyTo,
				// Whether anyone is actually copied, so the footer only offers Reply All when
				// there is a group for it to reach.
				cc.length > 0,
				settingsUrl,
				venue
			);

			// Post to the resend API using the API key
			const post = () =>
				fetch('https://api.resend.com/emails', {
					method: 'POST',
					headers: {
						'Content-Type': 'application/json',
						Authorization: `Bearer ${RESEND_API_KEY}`
					},
					body: JSON.stringify({
						from: FROM_EMAIL,
						// Mail is sent by a robot, but a reply has to reach people. Without this
						// header every reply to a notification — a question about a proposal, a
						// disputed transaction — is delivered to an unmonitored mailbox and lost.
						// Mail about a venue replies to the venue (resolve_venue_reply_to), a notice
						// ABOUT a specific person carries that person, and the rest belongs with
						// the stewards.
						reply_to: replyTo ?? SUPPORT_EMAIL,
						to: to,
						// Spread rather than `cc: cc`. Resend treats `cc: []` as a malformed
						// field rather than an absent one, and an absent header is what every
						// single-recipient email has always sent.
						...(cc.length > 0 ? { cc } : {}),
						subject: subject,
						html,
						text
					})
				});

			// Resend allows 10 requests a second per team, and a fan-out -- a call for bids, the
			// Monday digest, an import -- can post more than that at once. A 429 means nothing
			// was sent, so it is safe to try once more after the wait Resend asks for. Only once,
			// and briefly: pg_net gives this whole request five seconds, and a longer wait would
			// be recorded as a timeout on a message that might then be sent anyway.
			let res = await post();
			if (res.status === 429) {
				const asked = Number(res.headers.get('retry-after'));
				const wait = Math.min(Number.isFinite(asked) && asked > 0 ? asked * 1000 : 1000, 1200);
				await new Promise((resolve) => setTimeout(resolve, wait + Math.random() * 300));
				res = await post();
			}

			// Resend answers 4xx/5xx with a JSON body explaining why — an unverified sender
			// domain, a rejected recipient, a rate limit, a bad key. `fetch` does not throw
			// for those, so without this check the rejection was parsed, stringified, and
			// returned as a 200: the caller saw success and the mail silently never arrived.
			// Fail loudly instead. pg_net records the status, so a refused send is visible in
			// net._http_response rather than being indistinguishable from a delivered one.
			const data = await res.json().catch(() => null);
			if (!res.ok) {
				console.error('Resend rejected the message', res.status, data);
				return new Response(
					JSON.stringify({ error: 'Resend rejected the message', status: res.status, data }),
					{ status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
				);
			}
			returnData = JSON.stringify(data);
		}

		// Respond with success.
		return new Response(returnData, {
			status: 200,
			headers: { ...corsHeaders, 'Content-Type': 'application/json' }
		});
	} catch (error) {
		// Respond with an error.
		return new Response(
			JSON.stringify({ error: `Error sending email: ${JSON.stringify(error)}` }),
			{
				status: 400,
				headers: { ...corsHeaders, 'Content-Type': 'application/json' }
			}
		);
	}
};

// Serve the handler.
Deno.serve(handler);
