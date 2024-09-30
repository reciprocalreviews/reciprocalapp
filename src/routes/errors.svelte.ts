import { Errors, type ErrorID } from '$lib/data/Database';

// A global list of errors to display to the user, global to the application.
let errors = $state<ErrorID[]>([]);

export function addError(error: ErrorID) {
	errors = [...errors, error];
}

export function removeError(index: number) {
	errors = [...errors.slice(0, index), ...errors.slice(index + 1)];
}

export function getErrors(): ErrorID[] {
	return errors;
}

export function isError(error: string): error is ErrorID {
	return error in Errors;
}
