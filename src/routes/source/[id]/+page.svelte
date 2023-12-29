<script lang="ts">
	import { page } from '$app/stores';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Link from '$lib/components/Link.svelte';
	import Loading from '$lib/components/Loading.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import { getAuth, getDB } from '$lib/Context';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Slider from '$lib/components/Slider.svelte';
	import type Source from '$lib/types/Source';
	import { ORCIDRegex, type ScholarID } from '$lib/types/Scholar';
	import Form from '$lib/components/Form.svelte';
	import type { SourceID } from '$lib/types/Source';
	import type Scholar from '$lib/types/Scholar';
	import EditorsOnly from '$lib/components/EditorsOnly.svelte';

	const db = getDB();
	const auth = getAuth();

	/** The promise we're currently waiting for */
	let sourcePromise = db.getSource($page.params.id);
	let scholarPromise = $auth ? db.getScholar($auth.getScholarID()) : null;

	/** State for name edits */
	let editingNames = false;
	let name: string;
	let short: string;
	let link: string;

	/** State for pricing edits */
	let editingTokens = false;
	let submitCost: number;
	let reviewPay: number;
	let metaPay: number;
	let editPay: number;
	let newEditor: string;

	/** Whether we're confirming desire to archive */
	let archiving = false;

	function editNames(source: Source) {
		if (editingNames) {
			editingNames = false;
			source.name = name;
			source.short = short;
			source.link = link;
			sourcePromise = db.updateSource(source);
		} else {
			// Editing? Initialize all of the widgets with the current values.
			editingNames = true;
			name = source.name;
			short = source.short;
			link = source.link;
		}
	}

	function editTokens(source: Source) {
		if (editingTokens) {
			editingTokens = false;
			source.cost = {
				submit: submitCost,
				review: reviewPay,
				meta: metaPay,
				edit: editPay
			};
			sourcePromise = db.updateSource(source);
		} else {
			// Editing? Initialize all of the widgets with the current values.
			editingTokens = true;
			submitCost = source.cost.submit;
			reviewPay = source.cost.review;
			metaPay = source.cost.meta;
			editPay = source.cost.edit;
		}
	}

	function archive(source: Source) {
		source.archived = true;
		sourcePromise = db.updateSource(source);
	}

	function addEditor(source: Source, editor: ScholarID) {
		source.editors = Array.from(new Set([...source.editors, editor]));
		newEditor = '';
		sourcePromise = db.updateSource(source);
	}

	function removeEditor(source: Source, editor: ScholarID) {
		source.editors = source.editors.filter((ed) => ed !== editor);
		sourcePromise = db.updateSource(source);
	}

	function toggleSourceVolunteer(scholar: Scholar, id: SourceID) {
		scholar.sources = scholar.sources.includes(id)
			? scholar.sources.filter((s) => s !== id)
			: Array.from(new Set([...scholar.sources, id]));
		scholarPromise = db.updateScholar(scholar);
	}
</script>

{#await sourcePromise}
	<h1>Source</h1>
	<Loading />
{:then source}
	{@const editor = $auth !== null && source.editors.includes($auth.getScholarID())}

	{#if editingNames}
		<h1>
			<TextField padded={false} bind:text={name} size={name.length} placeholder="name" />
			<br /><TextField
				padded={false}
				bind:text={short}
				size={short.length + 2}
				placeholder="short name"
			/>
		</h1>
	{:else}
		<h1>
			{#if source.name.length === 0}<em>Unnamed</em>{:else}{source.name}{/if}
			{#if source.short.length > 0}({source.short}){/if}
		</h1>
	{/if}
	<p>
		{#if editingNames}<TextField
				bind:text={link}
				size={link.length}
				placeholder="URL"
			/>{:else}<Link to={source.link}>Official site</Link>{/if}
	</p>
	<EditorsOnly {editor}>
		<p>
			<Button action={() => editNames(source)}
				>{#if editingNames}Done{:else}Edit names and URL{/if}</Button
			>
		</p>

		{#if $auth && editor && !source.archived}
			<p>You're one of this source's editors.</p>
			<ul>
				<li>Edit this source's name, URL, editors, costs, and compensation.</li>
				<li>Send this page to your community to volunteer to review.</li>
				<li>
					Archive this publication if you no longer want to use <em>Reciprocal Reviews</em> to manage
					reviewing.
				</li>
			</ul>
		{/if}
	</EditorsOnly>
	{#if source.archived}
		<Feedback error>This source is archived. Volunteers are no longer accepted.</Feedback>
	{/if}

	<h2>Editors</h2>

	<p>
		Editors can edit source information, add and remove other editors, create and archive
		submissions, and gift review tokens. They are typically Editors-in-Chief of a journal (or their
		assistant), or Program Chairs of an archival conference.
	</p>

	{#each source.editors as editorID}
		<p>
			<ScholarLink id={editorID} />{#if editor}
				&nbsp;<Button
					active={source.editors.length > 1}
					action={() => removeEditor(source, editorID)}>remove</Button
				>{/if}
		</p>
	{/each}

	<EditorsOnly {editor}>
		<Form inline
			><TextField
				bind:text={newEditor}
				size={19}
				placeholder="ORCID"
				valid={(text) => ORCIDRegex.test(text)}
			/><Button active={ORCIDRegex.test(newEditor)} action={() => addEditor(source, newEditor)}
				>Add Editor</Button
			></Form
		>
	</EditorsOnly>

	<h2>Costs</h2>
	{#if editor}
		<p>
			<Button action={() => editTokens(source)}
				>{#if editingTokens}Done{:else}Edit{/if}</Button
			>
		</p>
	{/if}

	{#if source.cost.submit > 0}
		<p>
			Submissions cost {#if editingTokens}<Slider
					min={0}
					max={5}
					bind:value={submitCost}
					step={1}
				/>
			{/if}<Tokens amount={editingTokens ? submitCost : source.cost.submit} />. If you and your
			co-authors are short, volunteer below, or bid on a specific submission.
		</p>
	{:else}
		<p>Submissions are free.</p>
	{/if}

	<ul>
		<li>
			<strong>Reviewers</strong> are paid {#if editingTokens}<Slider
					min={0}
					max={3}
					bind:value={reviewPay}
					step={0.1}
				/>
			{/if}<Tokens amount={editingTokens ? reviewPay : source.cost.review} /> for each review.
		</li>
		<li>
			<strong>Metareviewers</strong> are paid {#if editingTokens}<Slider
					min={0}
					max={3}
					bind:value={metaPay}
					step={0.1}
				/>
			{/if}<Tokens amount={editingTokens ? metaPay : source.cost.meta} /> for each submission.
		</li>
		<li>
			<strong>Editors</strong> are paid {#if editingTokens}<Slider
					min={0}
					max={3}
					bind:value={editPay}
					step={0.1}
				/>
			{/if}<Tokens amount={editingTokens ? editPay : source.cost.edit} /> for each submission.
		</li>
	</ul>

	<h2>Volunteer</h2>
	{#if $auth && !source.archived}
		{#await scholarPromise}
			<Loading />
		{:then scholar}
			<p>
				When you volunteer to review for a source, your name will be public on the volunteer page of
				willing reviewers, along with the number of reviews you are seeking. If you stop reviewing,
				you will no longer be listed.
			</p>
			{#if scholar}
				<p>
					<Button action={() => toggleSourceVolunteer(scholar, source.id)}
						>{#if scholar.sources.includes(source.id)}Un-volunteer{:else}Volunteer{/if}</Button
					>
				</p>
			{/if}
		{:catch}
			<Feedback>Couldn't check volunteering status.</Feedback>
		{/await}
	{:else}
		<p>You need to log in to volunteer.</p>
	{/if}

	<p>See <Link to="/source/{$page.params.id}/volunteers">all volunteers</Link> for this source.</p>

	<EditorsOnly {editor}>
		<h2>Submissions</h2>

		<p>
			See the list of <Link to="/source/{$page.params.id}/submissions">submissions in review</Link>.
		</p>

		<h2>Archive</h2>
		<p>
			Archiving this source will remove it from the list of sources and prevent future submissions,
			transactions, and volunteers from being added. The history of transactions will be preserved.
		</p>
		<p>
			<Button action={() => (archiving = !archiving)}
				>{#if archiving}Cancel{:else}Archive...{/if}</Button
			>
		</p>
		{#if archiving}
			<Feedback error>Are you sure you want to archive this source?</Feedback>
			<p><Button action={() => archive(source)}>Archive</Button></p>
		{/if}
	</EditorsOnly>
{:catch}
	<h1>Unknown Source</h1>
	<Feedback>We couldn't load this source.</Feedback>
{/await}
