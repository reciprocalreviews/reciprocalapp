<script lang="ts">
	import Button from '$lib/components/Button.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { ORCIDRegex } from '$lib/types/Scholar';
	import { getAuth } from '../+layout.svelte';
	import Status from '$lib/components/Status.svelte';

	let email = $state('');

	function validORCID(text: string) {
		return /** TODO For testing */ text.length === 0 || ORCIDRegex.test(text);
	}

	function validEmail(email: string) {
		return /^\S+@\S+\.\S+$/.test(email);
	}

	let auth = getAuth();

	let error = $state<undefined | string>(undefined);
	let submitted = $state(false);

	async function login() {
		error = await auth.signIn(email);
		if (!error) submitted = true;
	}
</script>

<h1>Login</h1>

{#if auth.authenticated()}
	<p>You are logged in.</p>
{:else}
	<p>ORCID logins are coming. For now, enter your email to receive a one-time password.</p>
	<!-- <p>Login with your <Link to="https://orcid.org/">ORCID</Link> account.</p> -->

	<p>
		<TextField
			active={!submitted}
			name="email"
			size={19}
			bind:text={email}
			placeholder="email"
			valid={validEmail}
		/>
		<Button action={() => login()} active={!submitted && validEmail(email)}>Login</Button>
	</p>
{/if}

{#if submitted}
	<p><Status>Check your email for a sign in link.</Status></p>
{/if}
{#if error}
	<p><Status>{error}</Status></p>
{/if}
