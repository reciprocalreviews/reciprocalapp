<!-- This Source Code Form is subject to the terms of the Mozilla Public
  -- License, v. 2.0. If a copy of the MPL was not distributed with this
  -- file, You can obtain one at http://mozilla.org/MPL/2.0/.
  -->

<script lang="ts">
	import { goto } from '$app/navigation';
	import { Auth, getDB } from '$lib/Context';
	import MockAuthentication from '$lib/auth/MockAuthentication';
	import Button from '$lib/components/Button.svelte';
	import Link from '$lib/components/Link.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import createScholar from '$lib/data/createScholar';
	import { ORCIDRegex } from '$lib/types/Scholar';

	const db = getDB();

	let orcid = '';
	let password = '';

	async function login(id: string, pass: string) {
		if (!(validORCID(orcid) && validPassword(password))) return;

		id = id.length === 0 ? '0000-0001-7461-4783' : id;

		// Is there a scholar in the database for this ORCID ID?
		// If not, create one and give them some welcome tokens.
		await createScholar(db, id, 'Anonymous');

		// Authenticate.
		Auth.set(new MockAuthentication(id));

		// Go to the scholar's page.
		goto(`/scholar/${id}`);
	}

	function validORCID(text: string) {
		return /** TODO For testing */ text.length === 0 || ORCIDRegex.test(text);
	}
	function validPassword(pass: string) {
		return /** TODO For testing */ pass.length === 0 || pass.length > 0;
	}
</script>

<h1>Login</h1>

<p>Login with your <Link to="https://orcid.org/">ORCID</Link> account.</p>

<form on:submit|preventDefault={() => login(orcid, password)}>
	<TextField size={19} bind:text={orcid} placeholder="ORCID" valid={validORCID} />
	<TextField
		size={20}
		bind:text={password}
		type="password"
		placeholder="password"
		valid={validPassword}
	/>
	<Button submit action={() => {}} active={validORCID(orcid) && validPassword(password)}
		>submit</Button
	>
</form>
