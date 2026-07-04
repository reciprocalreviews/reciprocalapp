<script lang="ts">
	import { page } from '$app/state';
	import { PUBLIC_SUPABASE_URL } from '$env/static/public';
	import { getDB, type Result } from '$lib/data/CRUD';
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';
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

	// True only against the LOCAL Supabase stack — never staging or production, which point
	// at hosted supabase.co URLs and deliver the email for real. This mirrors the `resend`
	// edge function's own local check (supabase/functions/resend/index.ts). We gate the
	// clickable link on this (not merely non-prod) so a real verification token is never
	// surfaced in a hosted environment.
	const isLocal =
		PUBLIC_SUPABASE_URL.includes('127.0.0.1') || PUBLIC_SUPABASE_URL.includes('localhost');

	let email = $state('');
	let sent = $state(false);
	let unchanged = $state(false);
	let pending = $state('');
	let error = $state<undefined | ((l: LocaleText) => string)>(undefined);
	// Local-only convenience: we can't deliver the email locally (no Resend; the edge
	// function just logs), so we surface the verification link to make the flow testable.
	let devLink = $state<string | undefined>(undefined);

	let valid = $derived(validEmail(email));

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
			devLink = undefined;
			unchanged = true;
			return {};
		}

		unchanged = false;
		const result = await db().requestEmailVerification(trimmed, page.url.origin);
		if (result.error) {
			error = (l) => l.component.verifyEmail.feedback.error;
			sent = false;
			devLink = undefined;
			return { error: result.error };
		}
		error = undefined;
		sent = true;
		pending = trimmed;
		devLink = isLocal ? result.data?.url : undefined;
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
	<Feedback testid="verify-email-unchanged" text={(l) => l.component.verifyEmail.feedback.unchanged} />
{/if}

{#if sent}
	<Feedback
		testid="verify-email-sent"
		text={(l) => l.component.verifyEmail.feedback.sent.replace('{email}', pending)}
	/>
	{#if devLink}
		<!-- Dev-only convenience: production/staging deliver this link by email. It is a plain
		     anchor with SvelteKit preloading disabled — otherwise hover/viewport preload would
		     run the verify load and confirm the email before the link is clicked. -->
		<p class="devlink">
			<a
				href={devLink}
				data-sveltekit-preload-data="off"
				data-sveltekit-preload-code="off"
				data-testid="verify-email-devlink"><Text path={(l) => l.component.verifyEmail.devLink} /></a
			>
		</p>
	{/if}
{/if}

{#if error}
	<Feedback error text={error} />
{/if}

<style>
	.devlink {
		font-size: var(--small-font-size);
	}
</style>
