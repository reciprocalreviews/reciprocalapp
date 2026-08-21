<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { PUBLIC_SUPABASE_URL } from '$env/static/public';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import { ScholarLabel } from '$lib/components/Labels';
	import Note from '$lib/components/Note.svelte';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { generateORCID } from '$lib/data/ORCID';
	import type LocaleText from '$lib/locales/Locale';
	import { getAuth } from '../../Auth.svelte';

	let auth = getAuth();

	let error = $state<undefined | ((l: LocaleText) => string)>(undefined);

	// The ORCID callback bounces back here with ?error=orcid when the PKCE code exchange
	// fails (see src/routes/auth/callback/+server.ts). Without this the scholar lands on a
	// login page that looks like nothing happened. $derived rather than a one-time read so
	// it still resolves after a client-side navigation.
	let callbackError = $derived(
		page.url.searchParams.get('error') === 'orcid'
			? (l: LocaleText) => l.page.login.feedback.orcidError
			: undefined
	);

	// An error raised by an action on this page takes precedence over one carried in the
	// URL, so a fresh failure replaces the stale query-param message.
	let shownError = $derived(error ?? callbackError);

	// The dev-only controls (mock ORCID sign-in + seeded-user password grant) let us
	// exercise auth locally, where the real ORCID custom-OIDC provider cannot be
	// configured. Gated on the Supabase URL being local rather than on PUBLIC_ENV !==
	// 'prod': staging is a non-prod environment pointed at a hosted project, and it must
	// exercise the real ORCID path — otherwise the one environment that can validate
	// custom OIDC before production would be testing a mock instead, and would accumulate
	// throwaway @orcid.example auth users. Mirrors the same check in VerifyEmail.svelte.
	const devLogin =
		PUBLIC_SUPABASE_URL.includes('127.0.0.1') || PUBLIC_SUPABASE_URL.includes('localhost');
	let mockOrcidId = $state('');
	let mockOrcidName = $state('');
	let email = $state('');
	let password = $state('');

	// When the user is authenticated, redirect to their home page.
	$effect(() => {
		if (auth().isAuthenticated()) {
			goto(`/scholar/${auth().getUserID()}`);
		}
	});

	/** Real ORCID sign-in (production): redirect to the custom-OIDC provider. */
	async function signInWithORCID() {
		const authError = await auth().signInWithORCID(`${page.url.origin}/auth/callback`);
		if (authError) {
			console.error(authError);
			error = (l) => l.page.login.feedback.orcidError;
		} else {
			error = undefined;
		}
	}

	/** Local dev-only mock: create (or re-enter) a scholar to see the onboarding flow.
	 * A blank iD mints a fresh scholar (new-account onboarding); a reused iD returns to
	 * that account. */
	async function signInWithMockORCID() {
		const id = mockOrcidId.trim() || generateORCID();
		const name = mockOrcidName.trim() || 'Test Scholar';
		const response = await auth().signInWithMockORCID(id, name);
		if (typeof response === 'string') {
			error = undefined;
			goto(`/scholar/${response}`);
		} else {
			console.error(response);
			error = (l) => l.page.login.feedback.mockOrcidError;
		}
	}
</script>

<Page icon={ScholarLabel} title={(l) => l.page.login.title} breadcrumbs={[]}>
	{#if auth().isAuthenticated()}
		<Paragraph text={(l) => l.page.login.paragraph.loggedIn} />
	{:else}
		{#if devLogin}
			<Feedback text={(l) => l.page.login.feedback.mockOrcidDev} testid="mock-orcid-dev" />
		{/if}
		<Form>
			{#if devLogin}
				<TextField
					strings={(l) => l.page.login.field.orcidId}
					name="mock-orcid-id"
					size={19}
					bind:text={mockOrcidId}
					testid="mock-orcid-id"
				/>
				<TextField
					strings={(l) => l.page.login.field.name}
					name="mock-orcid-name"
					size={19}
					bind:text={mockOrcidName}
					testid="mock-orcid-name"
				/>
			{/if}
			<Button
				strings={devLogin ? (l) => l.page.login.button.mockOrcid : (l) => l.page.login.button.orcid}
				testid="orcid-signin"
				type="submit"
				action={devLogin ? signInWithMockORCID : signInWithORCID}
			/>
		</Form>

		{#if !devLogin}
			<Note path={(l) => l.page.login.note.orcid} />
		{/if}

		{#if devLogin}
			<Feedback text={(l) => l.page.login.feedback.passwordDev} testid="password-dev" />
			<Form>
				<TextField
					strings={(l) => l.page.login.field.email}
					name="email"
					size={19}
					bind:text={email}
					testid="email-input"
				/>
				<TextField
					strings={(l) => l.page.login.field.password}
					name="password"
					size={19}
					bind:text={password}
					testid="password-input"
				/>
				<Button
					strings={(l) => l.page.login.button.signIn}
					testid="password-submit"
					type="submit"
					action={async () => {
						const response = await auth().signInWithPassword(email, password);
						if (typeof response === 'string') {
							error = undefined;
							goto(`/scholar/${response}`);
						} else {
							console.error(response);
							error = (l) => l.page.login.feedback.signInError;
						}
					}}
					active={email.length > 0 && password.length > 0}
				/>
			</Form>
		{/if}
	{/if}

	{#if shownError}
		<Feedback error text={shownError} testid="login-error" />
	{/if}
</Page>
