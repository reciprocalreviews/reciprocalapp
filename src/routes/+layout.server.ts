import type { LocaleText } from '$lib/locales/Locale';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ cookies, params }) => {
	const lang = params.lang || 'en';

	// Dynamically import the correct translation file
	let locale: LocaleText | undefined = undefined;
	try {
		const strings = await import(`$lib/locales/lang/${lang}.json`);
		locale = strings.default as LocaleText;
	} catch (e) {
		// Fallback to default locale (e.g., 'en') if the requested locale is missing
		const strings = await import(`$lib/locales/lang/en.json`);
		locale = strings.default as LocaleText;
	}

	return {
		cookies: cookies.getAll(),
		locale
	};
};
