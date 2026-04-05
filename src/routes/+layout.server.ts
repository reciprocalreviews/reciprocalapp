import type { LocaleText } from '$lib/locales/Locale';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ cookies, params, fetch }) => {
	const lang = params.lang || 'en';

	// Dynamically import the correct translation file
	let locale: LocaleText | undefined = undefined;
	try {
		const strings = await fetch(`/locales/${lang}.json`);
		locale = (await strings.json()) as LocaleText;
	} catch (e) {
		// Fallback to default locale (e.g., 'en') if the requested locale is missing
		const strings = await fetch(`/locales/en.json`);
		locale = (await strings.json()) as LocaleText;
	}

	return {
		cookies: cookies.getAll(),
		locale
	};
};
