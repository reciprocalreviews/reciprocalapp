import monoEmoji from './monoEmoji';

export const CreateLabel = '+';
export const DeleteLabel = monoEmoji('✖');
export const ConfirmLabel = monoEmoji('✓');
export const EditLabel = monoEmoji('✎');
export const PrivateLabel = '•••';
export const EmptyLabel = '—';
export const UnknownLabel = monoEmoji('🔒');
export const DownLabel = '↓';
export const UpLabel = '↑';
export const FilterLabel = monoEmoji('🔎');
export const SubmissionLabel = monoEmoji('📄');
export const TokenLabel = '★';
export const TaskLabel = monoEmoji('☑️');
export const SettingsLabel = monoEmoji('⛭');
export const MinterLabel = monoEmoji('💰');
export const VenueLabel = monoEmoji('📚');
export const ScholarLabel = monoEmoji('👤');
export const IdeaLabel = monoEmoji('💡');
export const ErrorLabel = monoEmoji('⚠️');

export function plural(text: string, count: number | undefined | null) {
	return count === 1 ? text : text + 's';
}
