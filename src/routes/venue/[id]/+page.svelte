<script lang="ts">
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Link from '$lib/components/Link.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import { getDB } from '$lib/data/CRUD';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { ORCIDRegex } from '../../../data/ORCID';
	import { getAuth } from '../../Auth.svelte';
	import Page from '$lib/components/Page.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Card from '$lib/components/Card.svelte';
	import Note from '$lib/components/Note.svelte';
	import { DeleteLabel } from '$lib/components/Labels';
	import { validIdentifier, validURL, validEmail, validInteger } from '$lib/validation';
	import { handle } from '../../errors.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import Roles from './Roles.svelte';

	let { data } = $props();
	const { venue, currency, scholar, roles, commitments } = $derived(data);

	const db = getDB();
	const auth = getAuth();
	let editor = $derived(scholar && venue && venue.editors.includes(scholar.id));

	/** State for pricing edits */
	let editingTokens = $state(false);
	let submitCost: number = $state(0);
	let reviewPay: number = $state(0);
	let metaPay: number = $state(0);
	let editPay: number = $state(0);
	let newEditor: string = $state('');

	// /** Whether we're confirming desire to archive */
	// let archiving = $state(false);

	// function editTokens(source: Source) {
	// 	if (editingTokens) {
	// 		editingTokens = false;
	// 		source.cost = {
	// 			submit: submitCost,
	// 			review: reviewPay,
	// 			meta: metaPay,
	// 			edit: editPay
	// 		};
	// 		sourcePromise = db.updateSource(source);
	// 	} else {
	// 		// Editing? Initialize all of the widgets with the current values.
	// 		editingTokens = true;
	// 		submitCost = source.cost.submit;
	// 		reviewPay = source.cost.review;
	// 		metaPay = source.cost.meta;
	// 		editPay = source.cost.edit;
	// 	}
	// }

	// function archive(source: Source) {
	// 	source.archived = true;
	// 	sourcePromise = db.updateSource(source);
	// }

	// function toggleSourceVolunteer(scholar: Scholar, id: SourceID) {
	// 	const newSources = { ...scholar.sources };

	// 	// Remove the key
	// 	if (id in newSources) delete newSources[id];
	// 	// Add the source with an empty expertise list.
	// 	else newSources[id] = [];

	// 	scholar.sources = newSources;
	// 	scholarPromise = db.updateScholar(scholar);
	// }

	// function toggleSourceExpertise(scholar: Scholar, expertise: Expertise, yes: boolean) {
	// 	const currentExpertise = scholar.sources[sourceID] ?? [];
	// 	const newExpertise = yes
	// 		? Array.from(new Set([...currentExpertise, expertise.phrase]))
	// 		: currentExpertise.filter((exp) => exp !== expertise.phrase);
	// 	scholar.sources[sourceID] = newExpertise;
	// 	scholarPromise = db.updateScholar(scholar);
	// }

	// let newExpertise: string = $state('');
	// function addExpertise(source: Source, phrase: string) {
	// 	source.expertise = [...source.expertise, { phrase, deprecated: false, kind: 'topic' }];
	// 	sourcePromise = db.updateSource(source);
	// 	newExpertise = '';
	// }

	// function toggleExpertiseKind(source: Source, expertise: Expertise) {
	// 	source.expertise = source.expertise.map((exp) =>
	// 		exp.phrase === expertise.phrase
	// 			? { ...expertise, kind: expertise.kind === 'method' ? 'topic' : 'method' }
	// 			: exp
	// 	);
	// 	sourcePromise = db.updateSource(source);
	// }
</script>

{#if venue === null}
	<Page title="Unknown venue">
		<p>Unable to find this venue.</p>
	</Page>
{:else}
	<Page title={venue.title} subtitle="venue">
		<!-- Show the description -->
		{#if editor}
			<EditableText
				text={venue.description}
				placeholder="Venue description."
				inline={false}
				edit={(text) => db.editVenueDescription(venue.id, text)}
			/>{:else}<p>
				{#if venue.description.length === 0}<em>No description.</em>{:else}{venue.description}{/if}
			</p>{/if}
		<!-- Show the venue URL -->
		<Link to={venue.url}>{venue.url}</Link>
		<!-- Show metadata -->
		<Cards>
			<Card header="Editors">
				<ul>
					{#each venue.editors as editorID}
						<li>
							<ScholarLink id={editorID} />{#if editor && venue.editors.length > 1}
								&nbsp;<Button
									tip="Remove editor"
									active={venue.editors.length > 1}
									action={() =>
										handle(
											db.editVenueEditors(
												venue.id,
												venue.editors.filter((ed) => ed !== editorID)
											)
										)}>{DeleteLabel}</Button
								>{/if}
						</li>
					{/each}
				</ul>

				{#if editor}
					<form>
						<TextField
							bind:text={newEditor}
							size={19}
							placeholder="ORCID or email"
							valid={(text) => validEmail(text) || ORCIDRegex.test(text)}
						/><Button
							tip="Add editor"
							active={validEmail(newEditor) || ORCIDRegex.test(newEditor)}
							action={async () => {
								if (await handle(db.addVenueEditor(venue.id, newEditor))) newEditor = '';
							}}>Add editor</Button
						>
					</form>
				{/if}
				<Note>
					Editors can edit venue information, add and remove other editors, create and archive
					submissions, and gift review tokens. They are typically Editors-in-Chief of a journal or
					Program Chairs of a conference.
				</Note>
			</Card>
			<Card header="Currency">
				{#if currency}
					<p>
						This venue uses the <Link to="/currency/{venue.currency}">{currency.name}</Link> currency.
					</p>
				{:else}
					<Feedback error>Unable to load this venue's currency.</Feedback>
				{/if}

				<p>
					Newcomers receive <Tokens amount={venue.welcome_amount}></Tokens> when they volunteer to review.
				</p>
			</Card>
			{#if editor}
				<Card header="Settings" group="editors">
					<EditableText
						text={venue.title}
						label="title"
						placeholder=""
						valid={validIdentifier}
						edit={(text) => db.editVenueTitle(venue.id, text)}
					/>
					<EditableText
						text={venue.url}
						label="URL"
						placeholder="https://..."
						valid={validURL}
						edit={(text) => db.editVenueURL(venue.id, text)}
					/>
					<EditableText
						text={venue.welcome_amount.toString()}
						label="Welcome tokens"
						placeholder="e.g., 30"
						valid={validInteger}
						edit={(text) => db.editVenueWelcomeAmount(venue.id, parseInt(text))}
					/>
					<div>
						<Checkbox on={venue.bidding} change={(on) => db.editVenueBidding(venue.id, on)}
							>Allow bidding
						</Checkbox>
						<Note
							>{#if venue.bidding}Authenticated volunteers can see submissions and bid on them.{:else}Reviews
								are invitation only. Submissions are hidden and cannot be bid on.{/if}</Note
						>
					</div>
				</Card>
			{/if}
			<Card header="Volunteering" full>
				<p>
					These are the roles that volunteers can commit to. Create roles such as <em>reviewer</em>,
					<em>program commitee</em>, <em>associate editor</em> to represent the different kinds of contributions
					volunteers can make to this venue.
				</p>

				<h3>Roles</h3>
				<Roles {venue} {roles} editor={editor ?? false} />
			</Card>
		</Cards>
	</Page>
{/if}

<!-- <h2>Costs</h2>
{#if editor}
	<p>
		<Button tip="Editing cost" action={() => editTokens(source)}
			>{#if editingTokens}Done{:else}Edit{/if}</Button
		>
	</p>
{/if}

{#if source.cost.submit > 0}
	<p>
		Submissions cost {#if editingTokens}<Slider min={0} max={5} bind:value={submitCost} step={1} />
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

<p>
	See <Link to="/source/{$page.params.id}/volunteers">all volunteers</Link> for this source.
</p> -->

<!-- <Todo>Volunteering interface</Todo> -->

<!-- {#if uid && !source.archived}
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
						>{#if source.id in scholar.sources}Un-volunteer{:else}Volunteer{/if}</Button
					>
				</p>

				{#if source.id in scholar.sources}
					<p>What <strong>methods</strong> expertise do you have?</p>

					<p>
						{#each source.expertise.filter((exp) => !exp.deprecated && exp.kind === 'method') as expertise}
							<Checkbox
								on={scholar.sources[source.id].includes(expertise.phrase)}
								change={(on) => toggleSourceExpertise(scholar, expertise, on)}
								>{expertise.phrase}</Checkbox
							>
						{/each}
					</p>

					<p>What <strong>topical</strong> expertise do you have?</p>

					<p>
						{#each source.expertise.filter((exp) => !exp.deprecated && exp.kind === 'topic') as expertise}
							<Checkbox
								on={scholar.sources[source.id].includes(expertise.phrase)}
								change={(on) => toggleSourceExpertise(scholar, expertise, on)}
								>{expertise.phrase}</Checkbox
							>
						{/each}
					</p>

					<p>Write the editor if you have expertise not listed here.</p>
				{/if}
			{/if}
		{:catch}
			<Feedback>Couldn't check volunteering status.</Feedback>
		{/await}
	{:else}
		<p>You need to log in to volunteer.</p>

		<p>These are the <strong>methods</strong> expertise this journal currently seeks.</p>

		<p>
			<Tags>
				{#each source.expertise.filter((exp) => exp.kind === 'method') as expertise}{#if !expertise.deprecated}<Tag
							>{expertise.phrase}</Tag
						>{/if}{/each}
			</Tags>
		</p>

		<p>These are the <strong>topical</strong> expertise this journal currently seeks.</p>

		<p>
			<Tags>
				{#each source.expertise.filter((exp) => exp.kind === 'topic') as expertise}{#if !expertise.deprecated}<Tag
							>{expertise.phrase}</Tag
						>{/if}{/each}
			</Tags>
		</p>
	{/if} -->

<!-- <EditorsOnly {editor}>
	<h2>Submissions</h2>

	<p>
		See the list of <Link to="/source/{$page.params.id}/submissions">submissions in review</Link>.
	</p>

	<h2>Expertise</h2>

	<p>
		Define expertise phrases that reviewers can indicate to help identify reviewers. We recommend
		curating this as a community, to accurately reflect how reviewers wish to represent their
		expertise.
	</p>

	<p>
		<TextField label="expertise" placeholder="description" bind:text={newExpertise} />
		<Button
			tip="Add expertise"
			action={() => addExpertise(source, newExpertise)}
			active={newExpertise.length > 0}>+ expertise</Button
		>
	</p>

	<Table>
		{#each source.expertise as expertise}
			<tr>
				<td>
					<Tag>{expertise.phrase}</Tag>
				</td>
				<td>
					<Checkbox
						on={expertise.deprecated}
						change={async () => {
							return undefined;
						}}>deprecated</Checkbox
					>
				</td>
				<td>
					<div
						role="button"
						tabindex="0"
						style:cursor="pointer"
						style:user-select="none"
						onclick={() => toggleExpertiseKind(source, expertise)}
						onkeydown={() => toggleExpertiseKind(source, expertise)}
					>
						<Status good={expertise.kind === 'topic'}>{expertise.kind}</Status>
					</div>
				</td>
			</tr>
		{/each}
	</Table>

	<h2>Archive</h2>
	<p>
		Archiving this source will remove it from the list of sources and prevent future submissions,
		transactions, and volunteers from being added. The history of transactions will be preserved.
	</p>
	<p>
		<Button tip="Archive venue" action={() => (archiving = !archiving)}
			>{#if archiving}Cancel{:else}Archive...{/if}</Button
		>
	</p>
	{#if archiving}
		<Feedback error>Are you sure you want to archive this source?</Feedback>
		<p><Button tip="Confirm archive venue" action={() => archive(source)}>Archive</Button></p>
	{/if}
</EditorsOnly> -->
