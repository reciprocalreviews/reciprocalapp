import { invalidateAll } from '$app/navigation';
import { type DBError, type Result } from '$lib/data/CRUD';
import type { PostgrestError } from '@supabase/supabase-js';

export type Level = 'error' | 'warning' | 'success';
export type Feedback = { message: string; level: Level; error?: PostgrestError | undefined };

// A global list of errors to display to the user, global to the application.
let messages = $state<Feedback[]>([]);

export function addFeedback(message: string, level: Level, error?: PostgrestError | undefined) {
	messages = [...messages, { message, level, error }];
}

export function addError(error: DBError) {
	addFeedback(error.message, 'error', error.details);
}

export async function handle(
	action: Promise<Result<any>>,
	success?: string | undefined
): Promise<boolean> {
	const { error } = await action;
	if (error) {
		addError(error);
		return false;
	} else {
		if (success) addFeedback(success, 'success');
		invalidateAll();
		return true;
	}
}

export function removeError(index: number) {
	messages = [...messages.slice(0, index), ...messages.slice(index + 1)];
}

export function getFeedback(): Feedback[] {
	return messages;
}
