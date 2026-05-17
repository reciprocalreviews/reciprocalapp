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
	const emails: Email[] = [];
	const now = new Date();

	// Find venues that have opted into reminders and are due based on their
	// per-venue frequency. The cron runs daily; gating happens here.
	const { data: venues, error: venuesError } = await supabase
		.from('venues')
		.select(
			'id, admins, currency, transaction_reminder_frequency_days, transaction_reminder_time, currencies!currency(minters)'
		)
		.gt('transaction_reminder_frequency_days', 0);

	if (venues === null) {
		console.error('Error fetching venues for reminders', venuesError);
		return emails;
	}

	const dueVenues = venues.filter((venue) => {
		if (!venue.transaction_reminder_time) return true;
		const last = new Date(venue.transaction_reminder_time).getTime();
		const intervalMs = venue.transaction_reminder_frequency_days * 24 * 60 * 60 * 1000;
		return now.getTime() - last >= intervalMs;
	});

	if (dueVenues.length === 0) return emails;

	const dueVenueIds = dueVenues.map((v) => v.id);

	// Fetch unapproved proposed transactions for those venues only.
	const { data: unapprovedTransactions, error: unapprovedTransactionsError } = await supabase
		.from('transactions')
		.select('id, from_venue')
		.eq('status', 'proposed')
		.in('from_venue', dueVenueIds);

	if (unapprovedTransactions === null) {
		console.error('Error fetching unapproved transactions', unapprovedTransactionsError);
		return emails;
	}

	// Group transaction IDs by venue so each recipient is told how many
	// transactions are outstanding in venues they're responsible for.
	const transactionsByVenue = new Map<string, string[]>();
	for (const transaction of unapprovedTransactions) {
		if (!transaction.from_venue) continue;
		if (!transactionsByVenue.has(transaction.from_venue)) {
			transactionsByVenue.set(transaction.from_venue, []);
		}
		transactionsByVenue.get(transaction.from_venue)!.push(transaction.id);
	}

	// Fan out to admins + minters per venue. A scholar that serves both roles
	// across multiple venues gets one entry per venue's transaction list.
	const scholarsToRemind = new Map<string, string[]>();
	const venuesWithRecipients: string[] = [];

	for (const venue of dueVenues) {
		const txs = transactionsByVenue.get(venue.id) ?? [];
		// Even when there are no outstanding transactions, stamp the venue
		// below so we don't immediately re-check on the next cron tick.
		if (txs.length === 0) {
			venuesWithRecipients.push(venue.id);
			continue;
		}

		const minters = venue.currencies?.minters ?? [];
		const recipients = new Set<string>([...venue.admins, ...minters]);

		for (const recipient of recipients) {
			if (!scholarsToRemind.has(recipient)) scholarsToRemind.set(recipient, []);
			scholarsToRemind.get(recipient)!.push(...txs);
		}
		venuesWithRecipients.push(venue.id);
	}

	const recipientIds = Array.from(scholarsToRemind.keys());

	if (recipientIds.length > 0) {
		const { data: scholarsWithTasks } = await supabase
			.from('scholars')
			.select('id, email')
			.in('id', recipientIds);

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
	}

	// Stamp every due venue, including those with zero outstanding transactions,
	// so the next eligible check honors the configured frequency.
	if (venuesWithRecipients.length > 0) {
		const { error: stampError } = await supabase
			.from('venues')
			.update({ transaction_reminder_time: now.toISOString() })
			.in('id', venuesWithRecipients);
		if (stampError) console.error('Error stamping transaction_reminder_time', stampError);
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
