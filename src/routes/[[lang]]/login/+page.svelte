<script lang="ts">
	import Button from '$lib/components/Button.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { getAuth } from '../../Auth.svelte';
	import Note from '$lib/components/Note.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import { goto } from '$app/navigation';
	import Page from '$lib/components/Page.svelte';
	import { ScholarLabel } from '$lib/components/Labels';

	let email = $state('');

	// function validORCID(text: string) {
	// 	return text.length === 0 || ORCIDRegex.test(text);
	// }

	let auth = getAuth();

	let error = $state<undefined | string>(undefined);
	let submitted = $state(false);
	let password = $state('');

	// When the user is authenticated, redirect to their home page.
	$effect(() => {
		if (auth.isAuthenticated()) {
			goto(`/scholar/${auth.getUserID()}`);
		}
	});
</script>

<Page icon={ScholarLabel} title={(l) => l.page.login.title} breadcrumbs={[['/', 'Home']]}>
	{#if auth.isAuthenticated()}
		<p>You are logged in.</p>
	{:else}
		<!-- <p>Login with your <Link to="https://orcid.org/">ORCID</Link> account.</p> -->

		<Feedback
			error
			text="We're still implementing ORCID authentication. For now, enter your email for a one time
			password."
		/>

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
					const authError = await auth.signIn(email, undefined);
					if (authError) {
						console.error(authError);
						error = 'Unable to send one-time password.';
					} else {
						error = undefined;
						submitted = true;
					}
				}}
				active={!submitted}
			/>
		</Form>

		{#if submitted}
			<Feedback text="Check your email for a sign in code." />
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
						const response = await auth.signIn(email, password);
						if (typeof response === 'string') {
							error = undefined;
							submitted = false;
							goto(`/scholar/${response}`);
						} else {
							console.error(response);
							error = 'Unable to sign in.';
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
