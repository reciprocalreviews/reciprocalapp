import { invalidateAll } from '$app/navigation';
import { type DBError, type Result } from '$lib/data/CRUD';
import { collapseNotifications } from '$lib/data/notifications';
import type { AuthError, PostgrestError } from '@supabase/supabase-js';

export type Level = 'error' | 'warning' | 'success';
export type Feedback = {
	message: string;
	level: Level;
	error?: PostgrestError | AuthError | undefined;
	/** How many FURTHER notifications this banner stands for, when a batch of one kind was
	 * collapsed into it. Absent on an ordinary banner, and never 0. Banners.svelte turns it
	 * into "… — and N others"; the wording lives there because it needs locale, which this
	 * module does not have. */
	others?: number;
};

// A global list of errors to display to the user, global to the application.
let messages = $state<Feedback[]>([]);

// A global saving feedback counter.
let pendingActions = $state(0);

export function getPendingActions() {
	return pendingActions;
}

export function addFeedback(
	message: string,
	level: Level,
	error?: PostgrestError | AuthError | undefined,
	others?: number
) {
	messages = [...messages, { message, level, error, others }];
}

export function addError(error: DBError) {
	addFeedback(error.message, 'error', error.details);
}

/** Returns false if unsuccessful, true or the expected data if successful. */
export async function handle<T>(
	action: Promise<Result<T>>,
	success?: string | undefined
): Promise<T | boolean> {
	pendingActions++;
	let result: Result<T>;
	try {
		result = await action;
	} finally {
		// Always decrement, even if the action throws, so the global saving
		// indicator can't be pinned on by a failed action.
		pendingActions--;
	}
	const { data, error, notified } = result;
	if (error) {
		addError(error);
		return false;
	} else {
		// A generic "it worked" is worth saying only when the action didn't already say
		// something specific. Inviting one person to a role used to report both
		// "Invitations sent!" and "Manny Script was emailed …", which is the same news
		// twice — and the second one is strictly better, because it names who was told.
		// The generic message stays the fallback for when nothing was sent: a scholar with
		// no verified contact email is skipped by queue_email, and an invitation that
		// succeeded should not look like a click that did nothing.
		if (success && (notified === undefined || notified.length === 0))
			addFeedback(success, 'success');
		// One banner per notification, except that a batch of one kind collapses into a single
		// banner that names the first and counts the rest. One per recipient is right for the
		// one or two most actions have, and unusable for the ones that fan out: a call for bids
		// to a three-hundred-volunteer role filled the sticky header with three hundred bars,
		// each needing its own click. See collapseNotifications for the rules.
		if (notified) {
			for (const banner of collapseNotifications(notified))
				addFeedback(banner.message, 'success', undefined, banner.others);
		}
		// Awaited, so that callers resolve only once the page data reflects the write.
		// Returning first meant every caller was handed "success" while `data` from the
		// load functions was still the pre-write value — which is how a saved field could
		// show its old text for as long as the refetch took, and then flip to the new one.
		await invalidateAll();
		if (data) return data;
		else return true;
	}
}

export function removeError(index: number) {
	messages = [...messages.slice(0, index), ...messages.slice(index + 1)];
}

export function getFeedback(): Feedback[] {
	return messages;
}
