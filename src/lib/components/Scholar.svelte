<script lang="ts">
	import { getDB, getAuth } from '$lib/Context';
	import type Scholar from '$lib/types/Scholar';
	import Button from './Button.svelte';
	import Expertise from './Expertise.svelte';
	import Feedback from './Feedback.svelte';
	import Link from './Link.svelte';
	import Loading from './Loading.svelte';
	import Note from './Note.svelte';
	import SourceLink from './SourceLink.svelte';
	import Checkbox from './Checkbox.svelte';
	import Slider from './Slider.svelte';
	import Tokens from './Tokens.svelte';
	import Tag from './Tag.svelte';
	import { writable, type Writable } from 'svelte/store';
	import type Transaction from '$lib/types/Transaction';
	import Status from './Status.svelte';

	export let scholar: Scholar;

	const db = getDB();
	const auth = getAuth();

	const scholarTransactions: Writable<Transaction[] | undefined> = writable(undefined);

	$: minimum = scholar.minimum;

	async function setReviewing(on: boolean) {
		db.updateScholar({ ...scholar, reviewing: on });
		const newScholar = await db.getScholar(scholar.id);
		if (newScholar) scholar = newScholar;
	}

	async function handleChange(value: number) {
		db.updateScholar({ ...scholar, minimum: value });
		const newScholar = await db.getScholar(scholar.id);
		if (newScholar) scholar = newScholar;
	}

	$: db.getScholarTransactions(scholar.id).then((transactions) =>
		scholarTransactions.set(transactions)
	);
</script>

<h1>{scholar.name}</h1>
<Note>Joined {new Date(scholar.creationtime).toDateString()}</Note>
<p><Link to="https://orcid.org/{scholar.id}">ORCID Profile</Link></p>
{#if $auth && $auth.getScholarID() === scholar.id}<Button action={() => $auth?.logout()}
		>Logout</Button
	>{/if}

<h2>Expertise</h2>
<Expertise phrases={scholar.expertise} />

{#if $auth}
	<Note>Edit your expertise on <Link to="https://orcid.org/{scholar.id}">ORCID.org</Link>.</Note>
{/if}

<h2>Reviewing</h2>

<p>Currently volunteering for:</p>

{#each scholar.sources as sourceID}
	<p><SourceLink id={sourceID} /></p>
{/each}

{#await db.getEditedSources(scholar.id)}
	<Loading />
{:then sources}
	{#if sources.length > 0}
		<h2>Editing</h2>
		<p>Currently editor for:</p>
		{#each sources as source}
			<p><SourceLink id={source.id} /></p>
		{/each}
	{/if}
{:catch}
	<Feedback>Couldn't get editor roles.</Feedback>
{/await}

{#if $scholarTransactions === undefined}
	<Loading />
{:else}
	{@const netTokens = $scholarTransactions.reduce((total, trans) => (total += trans.amount), 0)}

	<h2>Availability</h2>

	<p>
		<Status>
			{#if scholar.reviewing && netTokens <= scholar.minimum}
				Seeking reviews.
			{:else}
				Not seeking reviews at this time.
			{/if}
		</Status>
	</p>

	{#if $auth !== null && $auth.getScholarID() === scholar.id}
		<p>
			<Checkbox on={scholar.reviewing} change={(on) => setReviewing(on)}
				>When checked, your profile will indicate you are available to review.</Checkbox
			>
		</p>
		{#if scholar.reviewing}
			<p>Only indicate I am available when I have fewer than...</p>
			<p>
				<Slider min={0} max={50} bind:value={minimum} step={1} change={handleChange} />
				<Tokens amount={scholar.minimum} />
			</p>
		{/if}

		<h2>Transactions</h2>

		<p>
			You have a total of <Tokens amount={netTokens} />.
		</p>

		<table>
			<thead>
				<tr><th>Purpose</th><th>Amount</th><th>Notes</th></tr>
			</thead>
			<tbody>
				{#each $scholarTransactions.sort((a, b) => b.creationtime - a.creationtime) as transaction}
					<tr
						><td><Tag>{transaction.purpose}</Tag></td><td><Tokens amount={transaction.amount} /></td
						><td>{transaction.description}</td></tr
					>
				{:else}
					No transactions
				{/each}
			</tbody>
		</table>
	{/if}
{/if}
