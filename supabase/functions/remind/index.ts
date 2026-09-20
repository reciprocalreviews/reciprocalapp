import 'edge-runtime';
import { createClient, SupabaseClient } from 'supabase';
import type { Database } from '../../../src/data/database.ts';
import { requireSecretKey } from '../_shared/auth.ts';
import type { EmailType } from '../_shared/templates.ts';

/**
 * One reminder, addressed to one scholar, named by the template that renders it.
 *
 * These used to carry a subject and a list of paragraphs written inline here, and were POSTed
 * straight to Resend. That made them the only mail the platform sent that nobody could switch
 * off, that never appeared in public.emails, that got no delivery reconciliation, and that
 * was missing from the data export DESIGN.md promises counts every message a scholar was
 * sent. They are queued through public.queue_reminder_email now, so all four follow from
 * going through the table — and a reminder can share the preference of the notice it chases.
 *
 * Nothing here builds a link's origin any more, either: templates own their URLs and the
 * origin is substituted at send time from the `site_url` vault secret, the same as every
 * other email. Only the venue path segment is resolved here.
 */
type PendingReminder = {
	scholar: string;
	event: EmailType;
	args: string[];
};

async function getStaleStatusReminder(
	supabase: SupabaseClient<Database>
): Promise<PendingReminder[]> {
	// Let's see which scholars have not updated their status in the last three months, and who haven't been sent a reminder in a month.
	const threeMonthsAgo = new Date();
	threeMonthsAgo.setDate(threeMonthsAgo.getDate() - 90);
	const oneMonthAgo = new Date();
	oneMonthAgo.setDate(oneMonthAgo.getDate() - 30);

	const reminders: PendingReminder[] = [];

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
		return reminders;
	}

	for (const scholar of staleScholars) {
		// No `if (scholar.email)` guard: queue_reminder_email resolves the address itself and
		// skips a scholar without a verified one, which is the same rule every other producer
		// now goes through rather than each checking for itself.
		//
		// Arguments are escaped at render time, so the status is passed through raw here.
		reminders.push({
			scholar: scholar.id,
			event: 'AvailabilityReminder',
			args: [scholar.status ?? '', scholar.id]
		});

		// Mark the scholar as reminded so we don't remind them again for another month.
		await supabase
			.from('scholars')
			.update({ status_reminder_time: new Date().toISOString() })
			.eq('id', scholar.id);
	}

	return reminders;
}

/**
 * Group a reminder by scholar AND venue.
 *
 * Three of the families below used to gather a scholar's links from every venue into one
 * message. Their templates are venue-scoped — a count, the venue's title, and a link to that
 * venue's submissions list — so the grouping has to be too: somebody who admins three venues
 * now gets three messages rather than one. That is more mail, and each piece of it is
 * actionable on its own, which the combined message was not.
 */
type ByScholarVenue = Map<string, Map<string, Set<string>>>;

function note(index: ByScholarVenue, scholar: string, venue: string, submission: string) {
	let venues = index.get(scholar);
	if (venues === undefined) index.set(scholar, (venues = new Map()));
	let submissions = venues.get(venue);
	if (submissions === undefined) venues.set(venue, (submissions = new Set()));
	submissions.add(submission);
}

async function getVenueReminders(supabase: SupabaseClient<Database>): Promise<PendingReminder[]> {
	const reminders: PendingReminder[] = [];
	const now = new Date();

	// Find venues that have opted into reminders and are due based on their
	// per-venue frequency. The cron runs daily; gating happens here. All four
	// reminder families below share this one cadence and the one stamp.
	const { data: venues, error: venuesError } = await supabase
		.from('venues')
		.select(
			'id, title, slug, admins, currency, transaction_reminder_frequency_days, transaction_reminder_time, currencies!currency(minters)'
		)
		.gt('transaction_reminder_frequency_days', 0);

	if (venues === null) {
		console.error('Error fetching venues for reminders', venuesError);
		return reminders;
	}

	const dueVenues = venues.filter((venue) => {
		if (!venue.transaction_reminder_time) return true;
		const last = new Date(venue.transaction_reminder_time).getTime();
		const intervalMs = venue.transaction_reminder_frequency_days * 24 * 60 * 60 * 1000;
		return now.getTime() - last >= intervalMs;
	});

	if (dueVenues.length === 0) return reminders;

	const dueVenueIds = dueVenues.map((v) => v.id);

	/** The path segment a venue is reached by: its web address once it has one, its id
	 * until then. Resolved here and passed as a template argument, the same division
	 * SupabaseCRUD's venuePathOf makes: a template owns the path in its prose and takes only
	 * the segment. A venue not in this batch cannot appear in any of them — every query is
	 * scoped to `dueVenueIds` — but the fallback keeps a link working rather than producing
	 * `/venue/undefined` if one ever did. */
	const venuePaths = new Map(dueVenues.map((v) => [v.id, v.slug ?? v.id]));
	const venuePathOf = (id: string) => venuePaths.get(id) ?? id;
	const venueTitles = new Map(dueVenues.map((v) => [v.id, v.title]));
	const venueTitleOf = (id: string) => venueTitles.get(id) ?? '';

	/** Turn one family's (scholar, venue) index into one reminder per pair. */
	const emit = (index: ByScholarVenue, event: EmailType) => {
		for (const [scholar, venues] of index)
			for (const [venue, submissions] of venues)
				reminders.push({
					scholar,
					event,
					args: [submissions.size.toString(), venueTitleOf(venue), venuePathOf(venue)]
				});
	};

	// ---- Family 1: proposed venue-sourced transactions → admins + minters ------

	const { data: unapprovedTransactions, error: unapprovedTransactionsError } = await supabase
		.from('transactions')
		.select('id, from_venue')
		.eq('status', 'proposed')
		.in('from_venue', dueVenueIds);

	if (unapprovedTransactions === null) {
		console.error('Error fetching unapproved transactions', unapprovedTransactionsError);
		return reminders;
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
	// Not grouped by venue, unlike families 3 to 5: this template sends the reader to their own
	// page, which lists everything awaiting them across every venue at once, so splitting the
	// message per venue would produce several mails pointing at the same list.
	for (const [scholar, transactions] of scholarsToRemind) {
		reminders.push({
			scholar,
			event: 'TransactionsPending',
			args: [transactions.length.toString(), scholar]
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
				event: 'SubmissionChargeReminder',
				args: [count.toString(), scholar]
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
		//
		// public.scholar_tasks draws the same line for the profile's Tasks table, and
		// family 4 below shares its "ready to be marked done" test. They are separate
		// definitions on purpose: this runs as service_role across every scholar from
		// bulk-fetched rows, so it cannot call a function keyed on auth.uid(). Change
		// one of the three and check the others.

		const pendingCompensation = assignments.filter(
			(a) => a.approved && !a.completed && a.compensation_requested_at !== null
		);
		const compensation: ByScholarVenue = new Map();
		for (const assignment of pendingCompensation)
			for (const approver of approversOf(assignment))
				note(compensation, approver, assignment.venue, assignment.submission);
		emit(compensation, 'CompensationPending');

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
			const ready: ByScholarVenue = new Map();
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
				for (const editor of editors) note(ready, editor.scholar, submission.venue, submission.id);
			}
			emit(ready, 'SubmissionsReady');

			// ---- Family 5: submissions with no editor → the venue's editors + admins
			// The mirror image of family 4, and the reason it needs its own family: family
			// 4 draws its recipients from the submission's own editors, so a submission
			// with none is silently dropped — the exact case where nobody has been told.
			// A submission arrives, its author is emailed about payment, and until someone
			// takes it on nothing else in the review can happen. Recipients come from the
			// venue instead: whoever volunteers for its priority-0 role (they can claim
			// it) plus its admins (they can assign someone).

			const { data: editorRoles, error: editorRolesError } = await supabase
				.from('roles')
				.select('id, venueid')
				.eq('priority', 0)
				.in('venueid', dueVenueIds);

			const { data: editorVolunteers, error: editorVolunteersError } =
				editorRoles === null || editorRoles.length === 0
					? { data: [], error: null }
					: await supabase
							.from('volunteers')
							.select('scholarid, roleid')
							.eq('active', true)
							.eq('accepted', 'accepted')
							.in(
								'roleid',
								editorRoles.map((role) => role.id)
							);

			if (editorRoles === null || editorVolunteers === null) {
				console.error(
					'Error fetching editor volunteers for reminders',
					editorRolesError ?? editorVolunteersError
				);
			} else {
				const venueOfRole = new Map(editorRoles.map((role) => [role.id, role.venueid]));
				const editorsByVenue = new Map<string, Set<string>>();
				for (const venue of dueVenues) editorsByVenue.set(venue.id, new Set(venue.admins ?? []));
				for (const volunteer of editorVolunteers) {
					const venueid = venueOfRole.get(volunteer.roleid);
					if (venueid !== undefined) editorsByVenue.get(venueid)?.add(volunteer.scholarid);
				}

				// Reuses the SubmissionsNeedEditors template rather than adding a reminder of
				// its own: this is the same news as the notice sent when the submission
				// arrived, and its template already takes exactly these three arguments.
				// So it is also governed by the same preference, which is what stops the
				// settings page offering "tell me" and "remind me" as separate checkboxes.
				const unclaimed: ByScholarVenue = new Map();
				for (const submission of reviewing) {
					const hasEditor = assignments.some(
						(a) => a.submission === submission.id && a.roles?.priority === 0 && a.approved
					);
					if (hasEditor) continue;
					for (const scholar of editorsByVenue.get(submission.venue) ?? [])
						note(unclaimed, scholar, submission.venue, submission.id);
				}
				emit(unclaimed, 'SubmissionsNeedEditors');
			}
		}
	}

	// Recipient addresses are no longer looked up here. queue_reminder_email resolves each
	// scholar server-side, skips anyone without a verified contact email, and skips anyone who
	// has silenced the preference governing the template — the same three rules every other
	// producer goes through, rather than a fourth copy of them living in this file.

	// Stamp every due venue, including those with nothing outstanding, so the
	// next eligible check honors the configured frequency.
	const { error: stampError } = await supabase
		.from('venues')
		.update({ transaction_reminder_time: now.toISOString() })
		.in('id', dueVenueIds);
	if (stampError) console.error('Error stamping transaction_reminder_time', stampError);

	return reminders;
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

		// Nothing here needs the origin any more. Templates own their links and the origin is
		// substituted at send time from the `site_url` vault secret, exactly as it is for
		// every other email — so a reminder from a test deployment now leads back to that
		// deployment for the same reason, and by the same mechanism, as the rest of the mail.
		const statusReminders = await getStaleStatusReminder(supabase);
		const venueReminders = await getVenueReminders(supabase);

		// Reminders are queued one per recipient, so one failure should not abandon the rest of
		// the run. Count them instead and report at the end — a cron job that reports success
		// while silently delivering nothing is the failure mode worth avoiding.
		//
		// What "queued" now means: a row in public.emails, whose AFTER INSERT trigger posts to
		// the resend function. So delivery, the branded shell, the reply path, the mail log and
		// the delivery reconciliation are all the shared pipeline's job rather than this
		// file's, and a reminder is finally something a scholar can point at and switch off.
		let rejected = 0;
		let queued = 0;

		for (const reminder of [...statusReminders, ...venueReminders]) {
			const { data, error } = await supabase.rpc('queue_reminder_email', {
				_event: reminder.event,
				_args: reminder.args,
				_scholar: reminder.scholar
			});
			if (error) {
				rejected++;
				console.error('Could not queue a reminder', reminder.event, reminder.scholar, error);
			} else {
				// Zero rows is not a failure: the scholar has no verified contact address, or
				// has silenced this notice. Both are the pipeline working.
				queued += data ?? 0;
			}
		}

		const attempted = statusReminders.length + venueReminders.length;
		if (rejected > 0) {
			return new Response(
				JSON.stringify({ error: 'Could not queue reminders', rejected, attempted }),
				{ status: 502, headers: { 'Content-Type': 'application/json' } }
			);
		}

		// Respond with success, saying how many actually became mail. `attempted` and `queued`
		// differ by the recipients who had nothing to receive it at, or did not want it.
		return new Response(JSON.stringify({ attempted, queued }), {
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
