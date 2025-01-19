export function validEmail(text: string) {
	return /.+@.+\..+/.test(text);
}

export function validEmails(text: string) {
	return text
		.split(',')
		.map((email) => email.trim())
		.every((email) => /.+@.+\..+/.test(email));
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
