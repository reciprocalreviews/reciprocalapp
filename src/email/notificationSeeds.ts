import { EmailPreferences, OptionalEmails, defaultFor } from './templates';

/**
 * The SQL that seeds `public.notification_preferences` and `public.optional_emails` from the
 * email registry.
 *
 * Those two tables are how the DATABASE answers "may this scholar be sent this?" — the
 * question `public.queue_email` has to answer at send time, and cannot answer by reading
 * TypeScript. They are therefore a copy of the registry, and a copy that drifts does not fail
 * loudly: it mails people notices they switched off, or silences ones they did not. So the
 * copy is generated rather than typed, and `src/email/templates.unit.ts` asserts that what is
 * committed in `supabase/schemas` matches what this produces.
 *
 * Run `node scripts/notification-seeds.js` to print it, then paste it over the seed block in
 * `supabase/schemas/notification_settings.sql` — and put the same block in a new migration,
 * since only migrations run on reset.
 */
export function seedSQL(): string {
	const preferences = [...OptionalEmails].sort();
	const mappings = [...EmailPreferences].sort((a, b) => a.event.localeCompare(b.event));
	const list = (values: string[]) => values.map((value) => `'${value}'`).join(', ');

	// Reconciled rather than appended: a preference that stops existing must stop governing.
	// The deletes come last because optional_emails references notification_preferences.
	return [
		'insert into public.notification_preferences (key, default_on) values',
		preferences.map((key) => `\t('${key}', ${defaultFor(key)})`).join(',\n'),
		'on conflict (key) do update set default_on = excluded.default_on;',
		'',
		'insert into public.optional_emails (event, preference) values',
		mappings.map((m) => `\t('${m.event}', '${m.preference}')`).join(',\n'),
		'on conflict (event) do update set preference = excluded.preference;',
		'',
		`delete from public.optional_emails where event not in (${list(mappings.map((m) => m.event))});`,
		`delete from public.notification_preferences where key not in (${list(preferences)});`
	].join('\n');
}
