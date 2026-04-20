import type { Result } from '$lib/data/CRUD';
import type LocaleText from '$lib/locales/Locale';
import type { Snippet } from 'svelte';

type PageHeader = {
	icon: string;
	title: string;
	wobble: boolean;
	subtitle: Snippet | undefined;
	details: Snippet | undefined;
	edit:
		| {
				valid: ((text: string) => ((l: LocaleText) => string) | undefined) | undefined;
				update: (text: string) => Promise<Result>;
				placeholder: (l: LocaleText) => string;
		  }
		| undefined;
};

export type { PageHeader as default };
