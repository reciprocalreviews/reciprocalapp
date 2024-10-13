<script lang="ts">
	import { goto } from '$app/navigation';
	import Button from '$lib/components/Button.svelte';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
	import Status from '$lib/components/Status.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import validEmails from '$lib/components/validEmails';
	import validURL from '$lib/components/validURL';
	import { getDB } from '$lib/data/CRUD';
	import { getAuth } from '../../Auth.svelte';
	import { addError, isError } from '../../errors.svelte';

	let venue = $state('');
	let editors = $state('');
	let url = $state('');
	let size = $state('');
	let message = $state('');
	let proposing = $state(false);

	const db = getDB();
	const auth = getAuth();

	function validName(text: string) {
		return text.length > 0;
	}

	function validSize(text: string) {
		return parseInt(text) > 0;
	}

	function validMessage(text: string) {
		return text.length > 0;
	}

	async function propose() {
		const uid = auth.getUserID();
		if (
			!validName(venue) ||
			!validEmails(editors) ||
			!validSize(size) ||
			!validMessage(message) ||
			uid === null
		)
			return;

		proposing = true;

		const proposal = await db.proposeVenue(
			uid,
			venue,
			url,
			editors.split(',').map((editor) => editor.trim()),
			parseInt(size),
			message
		);

		if (isError(proposal)) {
			addError(proposal);
			proposing = false;
		} else {
			goto(`/venues/proposal/${proposal}`);
		}
	}
</script>

<Page title="Propose a venue">
	<p>
		Venues are currently reviewed and approved by the <Link to="/about#managers">stewards</Link>, to
		ensure that only official editors and steering committees are creating venues.
	</p>

	<p>
		To propose a venue, share a few details about the venue, and the stewards will review them. Your
		proposal will appear publicly on the venues page, for others to support.
	</p>

	{#if auth.getUserID()}
		<form>
			<TextField bind:text={venue} label="venue" placeholder="name" valid={validName} />
			<TextField
				bind:text={editors}
				label="editors"
				placeholder="email1@email.com, email2@email.com"
				active={!proposing}
				valid={validEmails}
			/>
			<TextField
				bind:text={url}
				label="official venue URL"
				placeholder="https://..."
				active={!proposing}
				valid={validURL}
			/>
			<TextField
				bind:text={size}
				label="community size"
				placeholder="number"
				active={!proposing}
				valid={validSize}
			/>
			<TextField
				bind:text={message}
				label="why should the editors adopt Reciprocal Reviews?"
				inline={false}
				placeholder="why"
				active={!proposing}
				valid={validMessage}
			/>
			<Button
				tip="Propose venue"
				action={propose}
				active={!proposing &&
					validName(venue) &&
					validEmails(editors) &&
					validSize(size) &&
					validMessage(message)}>Propose venue</Button
			>
		</form>
	{:else}
		<Status good={false}>Log in to propose a venue.</Status>
	{/if}
</Page>
