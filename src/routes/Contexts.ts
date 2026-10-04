import type { LocaleText } from '#lib/locales/Locale.js';
import { getContext, setContext } from 'svelte';

export function setLocaleContext(locale: () => LocaleText) {
	setContext('locale', locale);
}

export function getLocaleContext() {
	return getContext<() => LocaleText>('locale');
}
