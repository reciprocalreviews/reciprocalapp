export default function monoEmoij(emoji: string) {
	return emoji.replaceAll('\uFE0F', '') + '\uFE0E';
}
