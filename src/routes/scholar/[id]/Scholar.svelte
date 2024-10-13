<script lang="ts">
	import { getDB } from '$lib/data/Database';
	import Link from '$lib/components/Link.svelte';
	import Loading from '$lib/components/Loading.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import type Transaction from '$lib/types/Transaction';
	import { getAuth } from '../../Auth.svelte';
	import Todo from '$lib/components/Todo.svelte';
	import type Scholar from '$lib/data/Scholar.svelte';
	import Status from '$lib/components/Status.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Card from '$lib/components/Card.svelte';
	import Cards from '$lib/components/Cards.svelte';

	let { scholar }: { scholar: Scholar } = $props();

	const db = getDB();
	const auth = getAuth();

	// Editable if the user is the scholar being viewed.
	let editable = $derived(auth.getUserID() === scholar.getID());

	let scholarTransactions: Transaction[] | undefined = $state(undefined);

	// $effect(() => {
	// 	db.getScholarTransactions(scholar.getID()).then((transactions) => {
	// 		scholarTransactions = transactions;
	// 	});
	// });

	async function update(text: string) {
		return await db.updateScholarName(scholar.getID(), text);
	}
</script>

<Cards>
	<Card header="identification">
		Joined {new Date(scholar.getJoined()).toLocaleDateString()}
		{#if editable}
			<EditableText
				text={scholar.getName() ?? ''}
				placeholder="name"
				label="name"
				change="Change name"
				save="Save name"
				empty="Anonymous"
				edit={(text) => db.updateScholarName(scholar.getID(), text)}
			/>
		{/if}

		{#if editable}<EditableText
				text={scholar.getEmail() ?? ''}
				label="email"
				placeholder="email"
				change="Change email"
				save="Save email"
				empty="no email"
				note="Your email will be public and only used to send notifications."
				valid={(text) => /.+@.+\..+/.test(text)}
				edit={(text) => db.updateScholarEmail(scholar.getID(), text)}
			/>{:else}{scholar.getEmail()}{/if}

		<p>
			{#if editable}
				Update your <Link to="https://orcid.org/{scholar.getORCID()}">ORCID Profile</Link> offsite.
			{:else}
				See this scholar's <Link to="https://orcid.org/{scholar.getORCID()}">ORCID Profile</Link>.
			{/if}
		</p>
	</Card>

	<Card header="availability">
		<Status good={scholar.isAvailable()}
			>{scholar.isAvailable() ? 'Available' : 'Unavailable'}</Status
		>
		{#if editable}
			<Checkbox
				on={scholar.isAvailable()}
				change={(on) => db.updateScholarAvailability(scholar.getID(), on)}
				>When checked, your profile will indicate you are available to review.</Checkbox
			>
		{/if}

		{#if editable}
			<EditableText
				inline={false}
				text={scholar.getStatus()}
				label="status"
				placeholder="Explain your current reviewing status to others."
				change="Edit status"
				save="Save status"
				empty="No status"
				edit={(text) => db.updateScholarStatus(scholar.getID(), text)}
				note="Your status is public and will be shown on your profile."
			/>
		{:else}
			{scholar.getStatus()}
		{/if}
	</Card>

	<Card header="volunteering">
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
		<!-- 
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
{/await} -->
	</Card>

	<Card header="transactions">
		{#if scholarTransactions === undefined}
			<Loading />
		{:else}
			<!-- {@const netTokens = scholarTransactions.reduce((total, trans) => (total += trans.amount), 0)} -->

			<h2>availability</h2>

			<!-- <p>
		<Status>
			I am {#if scholar.available && netTokens < scholar.minimum}
				available to review.
			{:else}
				not available to review.
			{/if}
		</Status>
	</p> -->

			{#if editable}
				<!-- {#if scholar.available}
			<p>Indicate I am available when I have fewer than...</p>
			<p>
				<Slider min={0} max={50} bind:value={minimum} step={1} change={handleChange} />
				<Tokens amount={scholar.minimum} />
			</p>
		{/if} -->

				<h2>transactions</h2>

				<Todo>Transaction list</Todo>

				<!-- <p>
			You have a total of <Tokens amount={netTokens} />.
		</p> -->

				<!-- <table>
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
		</table> -->
			{/if}
		{/if}
	</Card>
</Cards>
