import 'edge-runtime';
import { createClient, SupabaseClient } from 'supabase';
import type { Database } from '../../../src/data/database.ts';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const isLocal = Deno.env.get('PUBLIC_SUPABASE_URL')?.includes('127.0.0.1') ?? false;

type Email = {
	to: string;
	subject: string;
	message: string;
};

async function getStaleStatusReminder(supabase: SupabaseClient<Database>): Promise<Email[]> {
	// Let's see which scholars have not updated their status in the last three months, and who haven't been sent a reminder in a month.
	const threeMonthsAgo = new Date();
	threeMonthsAgo.setDate(threeMonthsAgo.getDate() - 90);
	const oneMonthAgo = new Date();
	oneMonthAgo.setDate(oneMonthAgo.getDate() - 30);

	const emails: Email[] = [];

	// Find all scholars that have a status that was updated more than three months ago.
	const { data: staleScholars, error: staleScholarsError } = await supabase
		.from('scholars')
		.select('id, status, email')
		.lte('status_time', threeMonthsAgo.toISOString())
		.or(`status_reminder_time.lte.${oneMonthAgo.toISOString()},status_reminder_time.is.null`);

	if (staleScholars === null) {
		console.error(
			'Error fetching stale scholars:',
			staleScholarsError.code,
			staleScholarsError.message
		);
		return emails;
	}

	for (const scholar of staleScholars) {
		if (scholar.email)
			emails.push({
				to: scholar.email,
				subject: 'Update your status',
				message: [
					'Hello,',
					"This is a friendly reminder to update your reviewing status on Reciprocal Reviews. Here's the last thing you wrote:",
					`"${scholar.status}"`,
					`You can update it here: https://reciprocal.reviews/scholar/${scholar.id}`,
					'(This is an automated message.)'
				].join('\n\n')
			});

		// Mark the scholar as reminded so we don't remind them again for another month.
		await supabase
			.from('scholars')
			.update({ status_reminder_time: new Date().toISOString() })
			.eq('id', scholar.id);
	}

	return emails;
}

async function getTransactionReminders(supabase: SupabaseClient<Database>): Promise<Email[]> {
	// Remind editors and minters of non-null from_venues of unapproved proposed transactions.
	const { data: unapprovedTransactions, error: unapprovedTransactionsError } = await supabase
		.from('transactions')
		.select('id, status, venues!from_venue(editors), currencies!currency(minters)')
		.eq('status', 'proposed')
		.not('from_venue', 'is', null);

	console.log(unapprovedTransactions?.length);

	const emails: Email[] = [];

	if (unapprovedTransactions === null) {
		console.error('Error fetching unapproved transactions', unapprovedTransactionsError);
		return emails;
	}

	// Convert the transactions to a list of scholars to remind, with their associated transactions to approve.
	const scholarsToRemind = new Map<string, string[]>();

	for (const transaction of unapprovedTransactions) {
		const editors = transaction.venues?.editors ?? [];
		const minters = transaction.currencies.minters;

		for (const editor of editors) {
			if (!scholarsToRemind.has(editor)) {
				scholarsToRemind.set(editor, []);
			}
			scholarsToRemind.get(editor)?.push(transaction.id);
		}

		for (const minter of minters) {
			if (!scholarsToRemind.has(minter)) {
				scholarsToRemind.set(minter, []);
			}
			scholarsToRemind.get(minter)?.push(transaction.id);
		}
	}

	const recipients = Array.from(scholarsToRemind.keys());

	// Get emails of all of the scholars
	const { data: scholarsWithTasks } = await supabase
		.from('scholars')
		.select('id, email')
		.in('id', recipients);

	if (scholarsWithTasks) {
		for (const recipient of scholarsWithTasks) {
			const transactions = scholarsToRemind.get(recipient.id);
			if (!recipient.email) continue;
			if (!transactions || transactions.length === 0) continue;
			emails.push({
				to: recipient.email,
				subject: 'Approve proposed transactions',
				message: [
					'Hello,',
					`You have ${transactions.length} proposed transaction(s) that require your approval.`,
					`Please review and approve it here: https://reciprocal.reviews/scholar/${recipient.id}`,
					'(This is an automated message.)'
				].join('\n\n')
			});
		}
	}
	return emails;
}

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

		const statusReminders = await getStaleStatusReminder(supabase);
		const transactionsReminders = await getTransactionReminders(supabase);

		for (const email of [...statusReminders, ...transactionsReminders]) {
			const { to, subject, message } = email;

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
		}

		// Respond with success.
		return new Response('reminded', {
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
