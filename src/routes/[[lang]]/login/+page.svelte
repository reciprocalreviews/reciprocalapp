<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { PUBLIC_ENV } from '$env/static/public';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import { ScholarLabel } from '$lib/components/Labels';
	import Note from '$lib/components/Note.svelte';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import type LocaleText from '$lib/locales/Locale';
	import { getAuth } from '../../Auth.svelte';

	let auth = getAuth();

	let error = $state<undefined | ((l: LocaleText) => string)>(undefined);

	// The dev-only email/password form is the seam the Playwright suite uses to sign in
	// without a real ORCID round-trip. It is never rendered in production; ORCID is the
	// sole authentication path there (#19).
	const devLogin = PUBLIC_ENV !== 'prod';
	let email = $state('');
	let password = $state('');

	// When the user is authenticated, redirect to their home page.
	$effect(() => {
		if (auth().isAuthenticated()) {
			goto(`/scholar/${auth().getUserID()}`);
		}
	});
</script>

<Page icon={ScholarLabel} title={(l) => l.page.login.title} breadcrumbs={[]}>
	{#if auth().isAuthenticated()}
		<Paragraph text={(l) => l.page.login.paragraph.loggedIn} />
	{:else}
		<Form>
			<Button
				strings={(l) => l.page.login.button.orcid}
				testid="orcid-signin"
				type="submit"
				action={async () => {
					const authError = await auth().signInWithORCID(`${page.url.origin}/auth/callback`);
					if (authError) {
						console.error(authError);
						error = (l) => l.page.login.feedback.orcidError;
					} else {
						error = undefined;
					}
				}}
			/>
		</Form>

		<Note path={(l) => l.page.login.note.orcid} />

		{#if devLogin}
			<Note path={(l) => l.page.login.note.dev} />
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

	{#if error}
		<Feedback error text={error} />
	{/if}
</Page>
