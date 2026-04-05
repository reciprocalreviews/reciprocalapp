<script lang="ts">
	import { goto } from '$app/navigation';
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

	let email = $state('');

	// function validORCID(text: string) {
	// 	return text.length === 0 || ORCIDRegex.test(text);
	// }

	let auth = getAuth();

	let error = $state<undefined | ((l: LocaleText) => string)>(undefined);
	let submitted = $state(false);
	let password = $state('');

	// When the user is authenticated, redirect to their home page.
	$effect(() => {
		if (auth().isAuthenticated()) {
			goto(`/scholar/${auth().getUserID()}`);
		}
	});
</script>

<Page icon={ScholarLabel} title={(l) => l.page.login.title} breadcrumbs={[['/', 'Home']]}>
	{#if auth().isAuthenticated()}
		<Paragraph text={(l) => l.page.login.paragraph.loggedIn} />
	{:else}
		<Feedback error text={(l) => l.page.login.feedback.orcidNote} />

		<Form>
			<TextField
				strings={(l) => l.page.login.field.email}
				active={!submitted}
				name="email"
				size={19}
				bind:text={email}
				testid="email-input"
			/>
			<Button
				strings={(l) => l.page.login.button.sendPassword}
				testid="email-submit"
				action={async () => {
					const authError = await auth().signIn(email, undefined);
					if (authError) {
						console.error(authError);
						error = (l) => l.page.login.feedback.sendPasswordError;
					} else {
						error = undefined;
						submitted = true;
					}
				}}
				active={!submitted}
			/>
		</Form>

		{#if submitted}
			<Feedback text={(l) => l.page.login.feedback.checkEmail} />
			<Form>
				<TextField
					strings={(l) => l.page.login.field.password}
					name="password"
					size={19}
					bind:text={password}
					testid="otp-input"
				/>
				<Button
					strings={(l) => l.page.login.button.signIn}
					testid="otp-submit"
					action={async () => {
						const response = await auth().signIn(email, password);
						if (typeof response === 'string') {
							error = undefined;
							submitted = false;
							goto(`/scholar/${response}`);
						} else {
							console.error(response);
							error = (l) => l.page.login.feedback.signInError;
						}
					}}
					active={password.length > 0}
				/>
			</Form>
		{/if}

		<Note path={(l) => l.page.login.note.orcid} />
	{/if}

	{#if error}
		<Feedback error text={error} />
	{/if}
</Page>
