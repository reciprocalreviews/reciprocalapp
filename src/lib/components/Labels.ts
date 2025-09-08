import monoEmoji from './monoEmoji';
import monoEmoij from './monoEmoji';

export const CreateLabel = '+';
export const DeleteLabel = monoEmoij('✖');
export const ConfirmLabel = monoEmoij('✓');
export const EditLabel = monoEmoij('✎');
export const PrivateLabel = '••••';
export const EmptyLabel = '—';
export const UnknownLabel = monoEmoij('🔒');
export const DownLabel = '↓';
export const UpLabel = '↑';
export const FilterLabel = monoEmoij('🔎');
export const SubmissionLabel = monoEmoij('📄');
export const TokenLabel = '★';
export const SettingsLabel = '⛭';
export const MinterLabel = monoEmoji('💰');

export function plural(text: string, count: number) {
	return count === 1 ? text : text + 's';
}
