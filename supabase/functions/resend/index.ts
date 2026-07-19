import z from 'zod';
import { requireSecretKey } from '../_shared/auth.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { renderBrandedEmail } from '../_shared/emailShell.ts';
import { Emails, renderEmail, type EmailType } from '../_shared/templates.ts';

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
	args: z.array(z.string()).nullish()
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

		// Render from the template registry when the queuing code did not supply a body.
		// An unknown event is a programming error, not something to deliver blank.
		let subject = parsed.subject ?? undefined;
		let message = parsed.message ?? undefined;
		if (subject === undefined || message === undefined) {
			if (!parsed.event || !(parsed.event in Emails))
				throw new Error(`Cannot render email: unknown event ${parsed.event}`);
			const rendered = renderEmail(parsed.event as EmailType, parsed.args ?? []);
			subject = rendered.subject;
			message = rendered.message;
		}

		let returnData;

		if (isLocal) {
			console.log('--- email sent ---');
			console.log('to: ', to);
			console.log('subject:', subject);
			console.log('message:', message);
			console.log('---');

			returnData = null;
		} else {
			// Wrap the stored plain-text body in the shared branded shell, sending
			// both an HTML version and a text/plain alternative.
			const { html, text } = renderBrandedEmail(subject, message);

			// Post to the resend API using the API key
			const res = await fetch('https://api.resend.com/emails', {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json',
					Authorization: `Bearer ${RESEND_API_KEY}`
				},
				body: JSON.stringify({
					from: 'notifications@reciprocal.reviews',
					to: to,
					subject: subject,
					html,
					text
				})
			});

			// Wait for the email to sent.
			const data = await res.json();
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
