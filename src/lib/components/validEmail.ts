export default function validEmail(text: string) {
	return /.+@.+\..+/.test(text);
}
