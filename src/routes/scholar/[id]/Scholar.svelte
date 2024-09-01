<script lang="ts">
	import { getDB } from '$lib/Context';
	import Feedback from '$lib/components/Feedback.svelte';
	import Link from '$lib/components/Link.svelte';
	import Loading from '$lib/components/Loading.svelte';
	import Note from '$lib/components/Note.svelte';
	import SourceLink from '$lib/components/SourceLink.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import type Transaction from '$lib/types/Transaction';
	import { getAuth } from '../../Auth.svelte';
	import type { Scholar } from '../../../data/types';
	import Todo from '$lib/components/Todo.svelte';
	import Name from './Name.svelte';

	let { scholar }: { scholar: Scholar } = $props();

	const db = getDB();
	const auth = getAuth();

	let editable = $state(auth.getUserID() === scholar.id);

	let scholarTransactions: Transaction[] | undefined = $state(undefined);

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

	$effect(() => {
		db.getScholarTransactions(scholar.id).then((transactions) => {
			scholarTransactions = transactions;
		});
	});
</script>

<Name {editable} {scholar} />

{#if auth.isAuthenticated()}
	<Note>Edit your expertise on <Link to="https://orcid.org/{scholar.id}">ORCID.org</Link>.</Note>
{/if}

<h2>Reviewing</h2>

<Todo>Venue volunteer list</Todo>
<!-- 
<p>Currently volunteering for:</p>

{#each Object.entries(scholar.sources) as [sourceID, expertise]}
	<p>
		<SourceLink id={sourceID} /><br /><Tags>
			{#each expertise as exp}<Tag>{exp}</Tag>{/each}
		</Tags>
	</p>
{/each} -->

{#await db.getEditedSources(scholar.id)}
	<Loading />
{:then sources}
	{#if sources.length > 0}
		<h2>Editing</h2>
		<p>Currently editor for:</p>
		<p>
			{#each sources as source}
				<SourceLink id={source.id} />
			{/each}
		</p>
	{/if}
{:catch}
	<Feedback>Couldn't get editor roles.</Feedback>
{/await}

{#if scholarTransactions === undefined}
	<Loading />
{:else}
	{@const netTokens = scholarTransactions.reduce((total, trans) => (total += trans.amount), 0)}

	<h2>Availability</h2>

	<!-- <p>
		<Status>
			I am {#if scholar.available && netTokens < scholar.minimum}
				available to review.
			{:else}
				not available to review.
			{/if}
		</Status>
	</p> -->

	{#if auth.getUserID() === scholar.id}
		<p>
			<Checkbox on={scholar.available} change={(on) => setReviewing(on)}
				>When checked, your profile will indicate you are available to review.
			</Checkbox>
		</p>
		<!-- {#if scholar.available}
			<p>Indicate I am available when I have fewer than...</p>
			<p>
				<Slider min={0} max={50} bind:value={minimum} step={1} change={handleChange} />
				<Tokens amount={scholar.minimum} />
			</p>
		{/if} -->

		<h2>Transactions</h2>

		<Todo>Transaction list</Todo>

		<p>
			You have a total of <Tokens amount={netTokens} />.
		</p>

		<table>
			<thead>
				<tr><th>Purpose</th><th>Amount</th><th>Notes</th></tr>
			</thead>
			<tbody>
				{#each scholarTransactions.sort((a, b) => b.creationtime - a.creationtime) as transaction}
					<tr>
						<td
							>{#if transaction.approvaltime}approved{:else}pending{/if}</td
						>
						<td><Tag>{transaction.purpose}</Tag></td><td><Tokens amount={transaction.amount} /></td
						><td>{transaction.description}</td></tr
					>
				{:else}
					<tr><td>No transactions</td></tr>
				{/each}
			</tbody>
		</table>
	{/if}
{/if}
