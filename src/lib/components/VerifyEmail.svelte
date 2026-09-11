<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import { getDB, type PendingEmailVerification, type Result } from '$lib/data/CRUD';
	import type LocaleText from '$lib/locales/Locale';
	import { validEmail } from '$lib/validation';
	import Button from './Button.svelte';
	import EditableText from './EditableText.svelte';
	import Feedback from './Feedback.svelte';
	import Form from './Form.svelte';
	import TextField from './TextField.svelte';

	// The scholar's current (verified) email, if any. When set, we show it with an Edit
	// affordance (change flow); when null, we show a plain prompt (onboarding).
	//
	// `pending` is what the database is still waiting to confirm, from
	// public.pending_email_verification. It is loaded by the page rather than held here,
	// because it has to survive a reload: before it existed, "we sent you a link" was a
	// boolean in this component's memory, so refreshing the page — or opening the profile
	// on a phone after reading the email on a laptop — showed the same empty form again,
	// with no sign a link was on its way and no way to ask for another.
	let {
		current = null,
		pending = null
	}: { current?: string | null; pending?: PendingEmailVerification | null } = $props();

	const db = getDB();

	let email = $state('');
	let sent = $state(false);
	let unchanged = $state(false);
	let sentTo = $state('');
	let error = $state<undefined | ((l: LocaleText) => string)>(undefined);

	/** Whether to show the address field even though something is already pending —
	 * because the scholar asked to verify a different address instead. */
	let entering = $state(false);

	let valid = $derived(validEmail(email));

	/** The live pending request, narrowed once so the template doesn't repeat the check. */
	let waiting = $derived(pending !== null && pending.pending ? pending : null);

	/** Whether the address field is on screen: always during onboarding with nothing
	 * pending, and on request once there is. */
	let asking = $derived(current === null && (waiting === null || entering));

	// A one-second tick, but only while a cooldown is actually running. `resend_after` is
	// an instant the database computed, so this counts down to the exact moment the RPC
	// starts accepting again rather than re-deriving "one minute" here and disagreeing
	// with it by a second. A permanent interval on a page that usually has nothing to
	// count would be a wakeup every second, forever.
	let now = $state(Date.now());
	$effect(() => {
		if (waiting === null) return;
		const until = Date.parse(waiting.resend_after);
		if (Date.now() >= until) return;
		const timer = setInterval(() => (now = Date.now()), 1000);
		return () => clearInterval(timer);
	});

	/** Seconds left before another request is accepted; 0 when it already is. */
	let remaining = $derived(
		waiting === null ? 0 : Math.max(0, Math.ceil((Date.parse(waiting.resend_after) - now) / 1000))
	);

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

	/** Request verification for `target`, recording UI state for the feedback.
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
		sentTo = trimmed;
		entering = false;
		// Refresh the load data so the pending block below shows the NEW created_at, and
		// therefore counts down from the right moment. This component calls the CRUD method
		// directly rather than through handle(), which is what normally does this.
		await invalidateAll();
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
{/if}

{#if waiting}
	<!-- Something is awaiting confirmation. Shown on every visit, not only the one that sent
	     it: the request lives in the database for 24 hours and outlives this page. -->
	{@const pendingEmail = waiting.email}
	<div class="pending">
		{#if waiting.delivery === 'failed' || waiting.delivery === 'unknown'}
			<!-- The message never left the building, so waiting for it is pointless. Takes
			     precedence over the clock: an unsent link's expiry is beside the point. -->
			<Feedback
				error
				inline={false}
				testid="verify-email-undelivered"
				text={(l) => l.component.verifyEmail.feedback.undelivered}
				inputs={{ email: pendingEmail }}
			/>
		{:else if waiting.expired}
			<Feedback
				warning
				inline={false}
				testid="verify-email-expired"
				text={(l) => l.component.verifyEmail.feedback.expired}
				inputs={{ email: pendingEmail }}
			/>
		{:else}
			<Feedback
				inline={false}
				testid="verify-email-pending"
				text={(l) => l.component.verifyEmail.feedback.pending}
				inputs={{
					email: pendingEmail,
					expires: new Date(waiting.expires_at).toLocaleString()
				}}
			/>
		{/if}

		<!-- Disabled rather than allowed to fail: the database refuses a second request
		     within a minute, and a button that answers with an error is worse than one that
		     says when it will work. -->
		<Button
			strings={(l) => l.component.verifyEmail.button.resend}
			testid="verify-email-resend"
			active={remaining === 0}
			action={() => request(pendingEmail)}
		/>

		{#if remaining > 0}
			<Feedback
				testid="verify-email-cooldown"
				text={(l) => l.component.verifyEmail.feedback.wait}
				inputs={{ seconds: String(remaining) }}
			/>
		{/if}

		{#if current === null && !entering}
			<Button
				strings={(l) => l.component.verifyEmail.button.different}
				testid="verify-email-different"
				action={() => (entering = true)}
			/>
		{/if}
	</div>
{/if}

{#if asking}
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
		text={(l) => l.component.verifyEmail.feedback.sent}
		inputs={{ email: sentTo }}
	/>
{/if}

{#if error}
	<Feedback error text={error} />
{/if}

<style>
	.pending {
		display: flex;
		flex-direction: column;
		align-items: start;
		gap: var(--spacing);
	}
</style>
