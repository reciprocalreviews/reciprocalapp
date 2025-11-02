import { ORCIDRegex } from './data/ORCID';

export function validEmail(text: string) {
	return /.+@.+\..+/.test(text);
}

export function validORCID(id: string) {
	return ORCIDRegex.test(id);
}

export function validEmails(text: string, length = 0) {
	const list = text.split(',').map((email) => email.trim());
	return list.every((email) => validEmail(email)) && list.length >= length;
}

export function validEmailsOrORCIDs(text: string) {
	return text
		.split(',')
		.map((id) => id.trim())
		.every((id) => validEmail(id) || validORCID(id));
}

export function isntEmpty(text: string) {
	return text.length > 0;
}

export function validURL(text: string) {
	return /https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)/.test(
		text
	);
}

export function validURLError(text: string): string | undefined {
	return validURL(text) ? undefined : 'Must be a valid URL';
}

export function validInteger(text: string) {
	return /[0-9]+/.test(text);
}
