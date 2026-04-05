import type { LocaleText } from '$lib/locales/Locale';
import { getContext, setContext } from 'svelte';

export function setLocaleContext(locale: () => LocaleText) {
	setContext('locale', locale);
}

export function getLocaleContext() {
	return getContext<() => LocaleText>('locale');
}
