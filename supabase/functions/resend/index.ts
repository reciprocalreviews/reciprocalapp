import z from 'zod';
import { corsHeaders } from '../_shared/cors.ts';
import { renderBrandedEmail } from '../_shared/emailShell.ts';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const isLocal = Deno.env.get('PUBLIC_SUPABASE_URL')?.includes('127.0.0.1') ?? false;

const ResendBodySchema = z.object({
	to: z.string().email(),
	subject: z.string(),
	message: z.string()
});

export type ResendBody = z.infer<typeof ResendBodySchema>;

const handler = async (request: Request): Promise<Response> => {
	// Permit client side requests
	if (request.method === 'OPTIONS') {
		return new Response('ok', { headers: corsHeaders });
	}

	try {
		/** Get the message body */
		const bodyJSON = await request.json();
		// Validate the message body
		const { to, subject, message } = ResendBodySchema.parse(bodyJSON);

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
