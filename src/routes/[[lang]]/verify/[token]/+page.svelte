<script lang="ts">
	import { invalidate } from '$app/navigation';
	import Feedback from '$lib/components/Feedback.svelte';
	import { ScholarLabel } from '$lib/components/Labels';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
	import VerifyEmail from '$lib/components/VerifyEmail.svelte';
	import Text from '$lib/locales/Text.svelte';
	import { getAuth } from '../../../Auth.svelte';

	let { data } = $props();

	let auth = getAuth();

	// On success, refresh the layout so scholars.email reloads and the unverified-email
	// banner clears. The server load already consumed the token, so this invalidate does
	// not re-run it (that load has no 'supabase:auth' dependency).
	$effect(() => {
		if (data.status === 'verified' && auth().isAuthenticated()) {
			invalidate('supabase:auth');
		}
	});

	// Whether there is a pending request this visitor is entitled to resend. The server
	// load only asks when the link expired, and only gets an answer for a signed-in
	// caller, so this is false for everyone else.
	let resendable = $derived(data.pending !== null && data.pending.pending);
</script>

<Page icon={ScholarLabel} title={(l) => l.page.verify.title}>
	{#if data.status === 'verified'}
		<Feedback testid="verify-verified" text={(l) => l.page.verify.verified} />
	{:else if data.status === 'expired'}
		<Feedback error testid="verify-expired" text={(l) => l.page.verify.expired} />
		{#if resendable}
			<!-- A dead end until now: the copy said "request a new one from your profile",
			     and the row this needs had just been deleted. Both are fixed, so the next
			     step is here rather than three navigations away. -->
			<Feedback text={(l) => l.page.verify.expiredSignedIn} />
			<VerifyEmail pending={data.pending} />
		{:else}
			<!-- Resending needs a session: request_email_verification is authenticated-only,
			     and it acts on auth.uid() rather than on the token. -->
			<Feedback text={(l) => l.page.verify.expiredSignedOut} />
		{/if}
	{:else if data.status === 'error'}
		<Feedback error testid="verify-error" text={(l) => l.page.verify.error} />
	{:else}
		<Feedback error testid="verify-invalid" text={(l) => l.page.verify.invalid} />
	{/if}

	{#if auth().isAuthenticated()}
		<Link to="/scholar/{auth().getUserID()}">
			<Text path={(l) => l.page.verify.profile} />
		</Link>
	{:else}
		<Link to="/login">
			<Text path={(l) => l.page.verify.login} />
		</Link>
	{/if}
</Page>
