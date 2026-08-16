import 'edge-runtime';
import { createClient, SupabaseClient } from 'supabase';
import type { Database } from '../../../src/data/database.ts';
import { requireSecretKey } from '../_shared/auth.ts';
import { escapeHtml, renderBrandedEmail } from '../_shared/emailShell.ts';

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
					`"${escapeHtml(scholar.status ?? '')}"`,
					`You can update it here: https://reciprocal.reviews/scholar/${scholar.id}`
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

/** A per-scholar reminder gathered by one of the venue reminder families;
 * recipient emails are resolved in bulk at the end of getVenueReminders. */
type PendingReminder = {
	scholar: string;
	subject: string;
	paragraphs: string[];
};

async function getVenueReminders(supabase: SupabaseClient<Database>): Promise<Email[]> {
	const emails: Email[] = [];
	const now = new Date();

	// Find venues that have opted into reminders and are due based on their
	// per-venue frequency. The cron runs daily; gating happens here. All four
	// reminder families below share this one cadence and the one stamp.
	const { data: venues, error: venuesError } = await supabase
		.from('venues')
		.select(
			'id, title, admins, currency, transaction_reminder_frequency_days, transaction_reminder_time, currencies!currency(minters)'
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
	const reminders: PendingReminder[] = [];

	// ---- Family 1: proposed venue-sourced transactions → admins + minters ------

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
	for (const venue of dueVenues) {
		const txs = transactionsByVenue.get(venue.id) ?? [];
		if (txs.length === 0) continue;
		const minters = venue.currencies?.minters ?? [];
		const recipients = new Set<string>([...venue.admins, ...minters]);
		for (const recipient of recipients) {
			if (!scholarsToRemind.has(recipient)) scholarsToRemind.set(recipient, []);
			scholarsToRemind.get(recipient)!.push(...txs);
		}
	}
	for (const [scholar, transactions] of scholarsToRemind) {
		reminders.push({
			scholar,
			subject: 'Approve proposed transactions',
			paragraphs: [
				`You have ${transactions.length} proposed transaction(s) that require your approval.`,
				`Please review and approve it here: https://reciprocal.reviews/scholar/${scholar}`
			]
		});
	}

	// ---- Family 2: proposed scholar-sourced charges → the charged scholar ------
	// Typically a co-author's share of a submission charge. Without this, a
	// co-author who missed the SubmissionCharged email is never asked again and
	// the submission sits unpaid indefinitely.

	const { data: scholarCharges, error: scholarChargesError } = await supabase
		.from('transactions')
		.select('id, from_scholar')
		.eq('status', 'proposed')
		.not('from_scholar', 'is', null)
		.in('to_venue', dueVenueIds);

	if (scholarCharges === null) {
		console.error('Error fetching proposed scholar charges', scholarChargesError);
	} else {
		const chargesByScholar = new Map<string, number>();
		for (const charge of scholarCharges) {
			if (!charge.from_scholar) continue;
			chargesByScholar.set(
				charge.from_scholar,
				(chargesByScholar.get(charge.from_scholar) ?? 0) + 1
			);
		}
		for (const [scholar, count] of chargesByScholar) {
			reminders.push({
				scholar,
				subject: 'Approve your submission charge',
				paragraphs: [
					`You have ${count} proposed charge(s) awaiting your approval — typically your share of a submission's cost. The submission may not proceed to review until every author has paid.`,
					`Review and approve here: https://reciprocal.reviews/scholar/${scholar}`
				]
			});
		}
	}

	// ---- Shared data for families 3 and 4: assignments in due venues -----------

	const { data: assignments, error: assignmentsError } = await supabase
		.from('assignments')
		.select(
			'id, venue, submission, scholar, role, approved, completed, compensation_requested_at, roles!role(priority, approver)'
		)
		.in('venue', dueVenueIds);

	if (assignments === null) {
		console.error('Error fetching assignments for reminders', assignmentsError);
	} else {
		const venueById = new Map(dueVenues.map((v) => [v.id, v]));
		const approvedBySubmission = new Map<string, typeof assignments>();
		for (const a of assignments) {
			if (!a.approved) continue;
			if (!approvedBySubmission.has(a.submission)) approvedBySubmission.set(a.submission, []);
			approvedBySubmission.get(a.submission)!.push(a);
		}

		/** The scholars who can compensate an assignment: venue admins, approved
		 * priority-0 assignees on the submission, and approved holders of the
		 * role's approver on the submission — the same union as
		 * can_approve_assignment, minus the assignee themselves. */
		const approversOf = (assignment: (typeof assignments)[number]): Set<string> => {
			const recipients = new Set<string>(venueById.get(assignment.venue)?.admins ?? []);
			for (const other of approvedBySubmission.get(assignment.submission) ?? []) {
				if (other.roles?.priority === 0) recipients.add(other.scholar);
				if (assignment.roles?.approver !== null && other.role === assignment.roles?.approver)
					recipients.add(other.scholar);
			}
			recipients.delete(assignment.scholar);
			return recipients;
		};

		// ---- Family 3: requested-but-unpaid compensation → the approver chain --
		// Only assignments whose scholar explicitly requested compensation:
		// approved-but-uncompleted alone means a review in progress, and nagging
		// approvers about those would teach them to ignore the reminder.

		const pendingCompensation = assignments.filter(
			(a) => a.approved && !a.completed && a.compensation_requested_at !== null
		);
		const compensationLinks = new Map<string, Set<string>>();
		for (const assignment of pendingCompensation) {
			const link = `https://reciprocal.reviews/venue/${assignment.venue}/submission/${assignment.submission}`;
			for (const approver of approversOf(assignment)) {
				if (!compensationLinks.has(approver)) compensationLinks.set(approver, new Set());
				compensationLinks.get(approver)!.add(link);
			}
		}
		for (const [scholar, links] of compensationLinks) {
			reminders.push({
				scholar,
				subject: 'Compensation requests await your approval',
				paragraphs: [
					`${links.size} submission(s) have completed work whose compensation is awaiting your approval:`,
					...links
				]
			});
		}

		// ---- Family 4: submissions ready to be marked done → priority-0 editors -
		// "Ready" = still reviewing, at least one compensated non-editor
		// assignment (so there was review work, and it has been paid), and no
		// approved non-editor assignment still uncompensated (the exact blocker
		// list mark_submission_done would report).

		const { data: reviewing, error: reviewingError } = await supabase
			.from('submissions')
			.select('id, venue')
			.eq('status', 'reviewing')
			.in('venue', dueVenueIds);

		if (reviewing === null) {
			console.error('Error fetching reviewing submissions', reviewingError);
		} else {
			const doneLinks = new Map<string, Set<string>>();
			for (const submission of reviewing) {
				const subAssignments = assignments.filter((a) => a.submission === submission.id);
				const hasCompensatedWork = subAssignments.some(
					(a) => (a.roles?.priority ?? 0) > 0 && a.completed
				);
				const hasBlockers = subAssignments.some(
					(a) => (a.roles?.priority ?? 0) > 0 && a.approved && !a.completed
				);
				const editors = subAssignments.filter(
					(a) => a.roles?.priority === 0 && a.approved && !a.completed
				);
				if (!hasCompensatedWork || hasBlockers || editors.length === 0) continue;
				const link = `https://reciprocal.reviews/venue/${submission.venue}/submission/${submission.id}`;
				for (const editor of editors) {
					if (!doneLinks.has(editor.scholar)) doneLinks.set(editor.scholar, new Set());
					doneLinks.get(editor.scholar)!.add(link);
				}
			}
			for (const [scholar, links] of doneLinks) {
				reminders.push({
					scholar,
					subject: 'Submissions may be ready to mark done',
					paragraphs: [
						`${links.size} submission(s) have all of their reviewing work compensated and may be ready to be marked done (which also settles editor compensation):`,
						...links
					]
				});
			}
		}
	}

	// ---- Resolve recipient emails in bulk and render the reminders -------------

	const recipientIds = Array.from(new Set(reminders.map((r) => r.scholar)));
	if (recipientIds.length > 0) {
		const { data: recipients } = await supabase
			.from('scholars')
			.select('id, email')
			.in('id', recipientIds);
		const emailById = new Map((recipients ?? []).map((s) => [s.id, s.email]));
		for (const reminder of reminders) {
			const to = emailById.get(reminder.scholar);
			if (!to) continue;
			emails.push({
				to,
				subject: reminder.subject,
				message: ['Hello,', ...reminder.paragraphs].join('\n\n')
			});
		}
	}

	// Stamp every due venue, including those with nothing outstanding, so the
	// next eligible check honors the configured frequency.
	const { error: stampError } = await supabase
		.from('venues')
		.update({ transaction_reminder_time: now.toISOString() })
		.in('id', dueVenueIds);
	if (stampError) console.error('Error stamping transaction_reminder_time', stampError);

	return emails;
}

const handler = async (request: Request): Promise<Response> => {
	// Only the cron job may trigger reminders. Without this check anyone holding the
	// (public) anon key could fire the daily run repeatedly, spamming scholars with
	// reminder mail and advancing the reminder timestamps that suppress the real run.
	const forbidden = await requireSecretKey(request);
	if (forbidden) return forbidden;

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
		const venueReminders = await getVenueReminders(supabase);

		// Reminders are sent one per recipient, so one rejection should not abandon the rest
		// of the run. Count them instead and report at the end — a cron job that reports
		// success while silently delivering nothing is the failure mode worth avoiding.
		let rejected = 0;

		for (const email of [...statusReminders, ...venueReminders]) {
			const { to, subject, message } = email;

			if (isLocal) {
				console.log('--- send this email ---');
				console.log('to: ', to);
				console.log('subject:', subject);
				console.log('message:', message);
				console.log('---');
			} else {
				// Wrap the plain-text reminder in the shared branded shell, sending
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
						to,
						subject,
						html,
						text
					})
				});
				// `fetch` does not throw on 4xx/5xx, so an unverified sender domain or a
				// rejected recipient would otherwise pass silently.
				const data = await res.json().catch(() => null);
				if (!res.ok) {
					rejected++;
					console.error('Resend rejected a reminder', res.status, to, data);
				}
			}
		}

		const attempted = statusReminders.length + venueReminders.length;
		if (rejected > 0) {
			return new Response(
				JSON.stringify({ error: 'Resend rejected reminders', rejected, attempted }),
				{ status: 502, headers: { 'Content-Type': 'application/json' } }
			);
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
