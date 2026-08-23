<script lang="ts">
	import { getDB, type Result } from '$lib/data/CRUD';
	import type LocaleText from '$lib/locales/Locale';
	import { validEmail } from '$lib/validation';
	import Button from './Button.svelte';
	import EditableText from './EditableText.svelte';
	import Feedback from './Feedback.svelte';
	import Form from './Form.svelte';
	import TextField from './TextField.svelte';

	// The scholar's current (verified) email, if any. When set, we show it with an Edit
	// affordance (change flow); when null, we show a plain prompt (onboarding).
	let { current = null }: { current?: string | null } = $props();

	const db = getDB();

	let email = $state('');
	let sent = $state(false);
	let unchanged = $state(false);
	let pending = $state('');
	let error = $state<undefined | ((l: LocaleText) => string)>(undefined);

	let valid = $derived(validEmail(email));

	/**
	 * Map the failure the database reported onto something the scholar can act on.
	 *
	 * `request_email_verification` distinguishes four causes and tags each with a `hint`
	 * (see supabase/schemas/email_verifications.sql), which PostgREST returns in the error
	 * body. We key off that rather than the message text so wording and localization stay
	 * free to change. Anything unrecognized falls back to the generic message — a new
	 * failure mode should read as a generic fault, never as the wrong specific one.
	 */
	function errorFor(result: Result): (l: LocaleText) => string {
		const details = result.error?.details as { hint?: string; code?: string } | undefined;
		switch (details?.hint) {
			case 'cooldown':
				return (l) => l.component.verifyEmail.feedback.cooldown;
			case 'not_configured':
				return (l) => l.component.verifyEmail.feedback.notConfigured;
			case 'auth_required':
				return (l) => l.component.verifyEmail.feedback.signedOut;
			case 'invalid_email':
				return (l) => l.component.verifyEmail.field.email.invalid;
		}
		// A caller with no valid session never reaches the function's own auth check: EXECUTE
		// is revoked from anon, so Postgres refuses first and returns 42501 with no hint. That
		// is the same situation as `auth_required` from the scholar's point of view.
		if (details?.code === '42501') return (l) => l.component.verifyEmail.feedback.signedOut;
		return (l) => l.component.verifyEmail.feedback.error;
	}

	/** Request verification for `target`, recording UI state for the feedback + dev link.
	 * Returns a plain Result so it can also drive EditableText's `edit`. */
	async function request(target: string): Promise<Result> {
		// Trim surrounding whitespace (the RPC also does, but keep the client honest).
		const trimmed = target.trim();

		// If it's the address already on file, there's nothing to verify — don't send an
		// email or a notification, just acknowledge it's unchanged. Compared case-
		// insensitively since verified addresses are stored lowercased.
		if (current !== null && trimmed.toLowerCase() === current.trim().toLowerCase()) {
			error = undefined;
			sent = false;
			unchanged = true;
			return {};
		}

		unchanged = false;
		const result = await db().requestEmailVerification(trimmed);
		if (result.error) {
			error = errorFor(result);
			sent = false;
			return { error: result.error };
		}
		error = undefined;
		sent = true;
		pending = trimmed;
		return {};
	}
</script>

{#if current !== null}
	<!-- Change flow: the current address shows with an Edit button; editing reveals a field
	     whose save sends a verification link. The stored address only changes once verified,
	     so EditableText correctly reverts to the current value after sending. -->
	<EditableText
		inline={false}
		text={current}
		strings={(l) => l.component.verifyEmail.field.email}
		testid="scholar-email"
		valid={(text) =>
			validEmail(text) ? undefined : (l) => l.component.verifyEmail.field.email.invalid}
		edit={request}
	/>
{:else}
	<!-- Onboarding: there is no current address to show, so prompt for one directly. -->
	<Form>
		<TextField
			strings={(l) => l.component.verifyEmail.field.email}
			name="verify-email"
			size={24}
			bind:text={email}
			testid="verify-email-input"
			valid={(text) =>
				validEmail(text) ? undefined : (l) => l.component.verifyEmail.field.email.invalid}
		/>
		<Button
			strings={(l) => l.component.verifyEmail.button.send}
			testid="verify-email-submit"
			type="submit"
			active={valid}
			action={() => request(email)}
		/>
	</Form>
{/if}

{#if unchanged}
	<Feedback
		testid="verify-email-unchanged"
		text={(l) => l.component.verifyEmail.feedback.unchanged}
	/>
{/if}

{#if sent}
	<Feedback
		testid="verify-email-sent"
		text={(l) => l.component.verifyEmail.feedback.sent.replace('{email}', pending)}
	/>
{/if}

{#if error}
	<Feedback error text={error} />
{/if}
