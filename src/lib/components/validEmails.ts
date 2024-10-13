export default function validEmails(text: string) {
	return text
		.split(',')
		.map((email) => email.trim())
		.every((email) => /.+@.+\..+/.test(email));
}
