export default function validEmails(text: string) {
	return text
		.split(',')
		.map((editor) => editor.trim())
		.every((editor) => /.+@.+\..+/.test(editor));
}
