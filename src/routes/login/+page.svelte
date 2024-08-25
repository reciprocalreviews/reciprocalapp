<script lang="ts">
	import Button from '$lib/components/Button.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { ORCIDRegex } from '$lib/types/Scholar';
	import Status from '$lib/components/Status.svelte';
	import Link from '$lib/components/Link.svelte';
	import { getAuth } from '../Auth.svelte';

	let orcid = $state('');

	function validORCID(text: string) {
		return text.length === 0 || ORCIDRegex.test(text);
	}

	let auth = getAuth();

	let error = $state<undefined | string>(undefined);
	let submitted = $state(false);

	async function login() {}
</script>

<h1>Login</h1>

{#if auth}
	<p>You are logged in.</p>
{:else}
	<p>Login with your <Link to="https://orcid.org/">ORCID</Link> account.</p>

	<p>
		<TextField
			active={!submitted}
			name="email"
			size={19}
			bind:text={orcid}
			placeholder="email"
			valid={validORCID}
		/>
		<Button action={() => login()} active={!submitted && validORCID(orcid)}>Login</Button>
	</p>
{/if}

{#if submitted}
	<p><Status>Check your email for a sign in link.</Status></p>
{/if}
{#if error}
	<p><Status>{error}</Status></p>
{/if}
