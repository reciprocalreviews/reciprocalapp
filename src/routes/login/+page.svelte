<script lang="ts">
	import Button from '$lib/components/Button.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { ORCIDRegex } from '$lib/types/Scholar';
	import Status from '$lib/components/Status.svelte';
	import Link from '$lib/components/Link.svelte';
	import { getAuth } from '../Auth.svelte';
	import Note from '$lib/components/Note.svelte';
	import Feedback from '$lib/components/Feedback.svelte';

	let email = $state('');

	// function validORCID(text: string) {
	// 	return text.length === 0 || ORCIDRegex.test(text);
	// }

	let auth = getAuth();

	let error = $state<undefined | string>(undefined);
	let submitted = $state(false);
	let password = $state('');
</script>

<h1>Login</h1>

{#if auth.isAuthenticated()}
	<p>You are logged in.</p>
{:else}
	<!-- <p>Login with your <Link to="https://orcid.org/">ORCID</Link> account.</p> -->

	<Feedback error
		>We're still implementing ORCID authentication. For now, enter your email for a one time
		password.</Feedback
	>

	<p>
		<TextField active={!submitted} name="email" size={19} bind:text={email} placeholder="email" />
		<Button
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
			active={!submitted}>Login</Button
		>
	</p>

	{#if submitted}
		<p><Status>Check your email for a sign in link.</Status></p>
		<p>
			<TextField name="password" size={19} bind:text={password} placeholder="one-time password" />
			<Button
				action={async () => {
					const authError = await auth.signIn(email, password);
					if (authError) {
						console.error(authError);
						error = 'Unable to sign in.';
					} else {
						error = undefined;
						submitted = false;
					}
				}}
				active={password.length > 0}>Login</Button
			>
		</p>
	{/if}

	<Note>
		Why ORCID? It's the de facto way to manage scholar identity. It's designed for this explicit
		purpose and there's no reason to require another login.
	</Note>
{/if}

{#if error}
	<Feedback error>{error}</Feedback>
{/if}
