import 'edge-runtime';
import { createClient } from 'supabase';
import type { Database } from '../../../src/data/database.ts';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const isLocal = Deno.env.get('PUBLIC_SUPABASE_URL')?.includes('127.0.0.1') ?? false;

const handler = async (): Promise<Response> => {
	try {
		// Get service role access to the database.
		const supabase = createClient<Database>(
			Deno.env.get('SUPABASE_URL') ?? '',
			Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
			{
				global: {
					headers: { Authorization: `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}` }
				}
			}
		);

		// Let's see which scholars have not updated their status in the last three months, and who haven't been sent a reminder in a month.
		const threeMonthsAgo = new Date();
		threeMonthsAgo.setDate(threeMonthsAgo.getDate() - 90);
		const oneMonthAgo = new Date();
		oneMonthAgo.setDate(oneMonthAgo.getDate() - 30);

		// Find all scholars that have a status that was updated more than three months ago.
		const { data: staleScholars } = await supabase
			.from('scholars')
			.select('id, status, email')
			.lte('status_time', threeMonthsAgo.toISOString())
			.or(`status_reminder_time.lte.${oneMonthAgo.toISOString()},status_reminder_time.is.null`);

		if (staleScholars) {
			for (const scholar of staleScholars) {
				const to = scholar.email;
				const subject = 'Update your status';
				const message = [
					'Hello,',
					"This is a friendly reminder to update your reviewing status on Reciprocal Reviews. Here's the last thing you wrote:",
					`"${scholar.status}"`,
					`You can update it here: https://reciprocal.reviews/scholar/${scholar.id}`,
					'This is an automated message.'
				].join('\n\n');

				if (isLocal) {
					console.log('--- send this email ---');
					console.log('to: ', to);
					console.log('subject:', subject);
					console.log('message:', message);
					console.log('---');
				} else {
					// Post to the resend API using the API key
					const res = await fetch('https://api.resend.com/emails', {
						method: 'POST',
						headers: {
							'Content-Type': 'application/json',
							Authorization: `Bearer ${RESEND_API_KEY}`
						},
						body: JSON.stringify({
							from: 'notifications@reciprocal.reviews',
							to,
							subject,
							text: message
						})
					});
					// Wait for the email to sent.
					await res.json();
				}
				// Mark the scholar as reminded so we don't remind them again for another month.
				await supabase
					.from('scholars')
					.update({ status_reminder_time: new Date().toISOString() })
					.eq('id', scholar.id);
			}
		}

		// Respond with success.
		return new Response(null, {
			status: 200,
			headers: { 'Content-Type': 'application/json' }
		});
	} catch (error) {
		// Respond with an error.
		return new Response(
			JSON.stringify({ error: `Error sending reminders: ${JSON.stringify(error)}` }),
			{
				status: 400,
				headers: { 'Content-Type': 'application/json' }
			}
		);
	}
};

// Serve the handler.
Deno.serve(handler);
