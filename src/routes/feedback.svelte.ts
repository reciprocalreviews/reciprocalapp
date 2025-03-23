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

export async function handle<T>(
	action: Promise<Result<T>>,
	success?: string | undefined
): Promise<T | boolean> {
	const { data, error } = await action;
	if (error) {
		addError(error);
		return false;
	} else {
		if (success) addFeedback(success, 'success');
		invalidateAll();
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
