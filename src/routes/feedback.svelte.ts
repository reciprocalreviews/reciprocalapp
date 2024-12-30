import { invalidateAll } from '$app/navigation';
import { Errors, type ErrorID } from '$lib/data/CRUD';

export type Level = 'error' | 'warning' | 'success';
export type Feedback = { message: ErrorID | string; level: Level };

// A global list of errors to display to the user, global to the application.
let messages = $state<Feedback[]>([]);

export function addFeedback(message: string, level: Level) {
	messages = [...messages, { message, level }];
}

export function addError(error: ErrorID) {
	addFeedback(error, 'error');
}

export async function handle(
	action: Promise<ErrorID | undefined>,
	success?: string | undefined
): Promise<boolean> {
	const errorID = await action;
	if (errorID) {
		addError(errorID);
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

export function isError(error: string): error is ErrorID {
	return error in Errors;
}
