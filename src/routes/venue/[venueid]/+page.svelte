<script lang="ts">
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Link from '$lib/components/Link.svelte';
	import { getDB } from '$lib/data/CRUD';
	import Page from '$lib/components/Page.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import { ConfirmLabel, DeleteLabel, ScholarLabel, TokenLabel } from '$lib/components/Labels';
	import { addFeedback, handle } from '../../feedback.svelte';
	import Roles from './Roles.svelte';
	import type { PageData } from './$types';
	import Dashboard from '$lib/components/Dashboard.svelte';
	import CurrencyLink from '$lib/components/CurrencyLink.svelte';
	import Form from '$lib/components/Form.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Options from '$lib/components/Options.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import { validURLError } from '$lib/validation';
	import Table from '$lib/components/Table.svelte';

	let { data }: { data: PageData } = $props();
	const {
		venue,
		currency,
		minters,
		scholar,
		roles,
		volunteers,
		tokens,
		submissionCount,
		types,
		compensation
	} = $derived(data);

	const db = getDB();
	let isAdmin = $derived(scholar && venue && venue.admins.includes(scholar.id));
	let isVolunteer = $derived(
		scholar && venue && volunteers && volunteers.some((v) => v.scholarid === scholar.id)
	);

	let compensationManuscript = $state('');
	let compensationRole = $state('');
	let compensationNote = $state('');
</script>

{#if venue === null}
	<Page title="Unknown venue" breadcrumbs={[]}>
		<p>Unable to find this venue.</p>
	</Page>
{:else}
	<Page
		title={venue.title}
		breadcrumbs={[[`/venues`, 'Venues']]}
		edit={isAdmin
			? {
					placeholder: 'Title',
					valid: (text) => (text.length > 0 ? undefined : 'Must include a title'),
					update: (text) => db().editVenueTitle(venue.id, text)
				}
			: undefined}
	>
		{#snippet subtitle()}Venue{/snippet}
		{#snippet details()}
			{#if isAdmin}
				<EditableText
					text={venue.url}
					placeholder="https://..."
					valid={validURLError}
					edit={(text) => db().editVenueURL(venue.id, text)}
				/>
			{:else}<Link to={venue.url}>{venue.url}</Link>{/if}{/snippet}

		<!-- Show the description -->
		{#if isAdmin}
			<EditableText
				text={venue.description}
				placeholder="Venue description."
				inline={false}
				edit={(text) => db().editVenueDescription(venue.id, text)}
			/>
		{:else}
			<p>
				{#if venue.description.length === 0}<em>No description.</em>{:else}{venue.description}{/if}
			</p>
		{/if}

		<ul>
			<!-- Prompt to pay -->
			<li>
				Submitted a manuscript? <Link to={`${venue.id}/submissions/new`}>Pay</Link> to start peer review.
			</li>
			<!-- Prompt to volunteer -->
			<li>
				Need tokens to pay? <Link to="#roles">Volunteer to review</Link>.
			</li>
			<!-- Key details about costs. -->
			<li>
				This venue uses {#if currency}the <CurrencyLink {currency}>
						{TokenLabel} {currency.name}</CurrencyLink
					>{:else}an unknown{/if}
				currency.
			</li>
		</ul>

		{#if isAdmin}
			<Feedback inline={false}>
				Welcome admin! Check the <Link to="/venue/{venue.id}/settings">settings</Link> page to edit venue
				compensation, roles, and anonymity.
			</Feedback>
		{/if}

		<Dashboard
			stats={[
				{
					number: venue.welcome_amount ?? undefined,
					icon: TokenLabel,
					title: 'tokens for new volunteers'
				},
				{
					number: venue.submission_cost ?? undefined,
					icon: TokenLabel,
					title: 'tokens for new submissions'
				},
				{
					number: volunteers?.length ?? undefined,
					title: 'volunteers',
					link: `/venue/${venue.id}/volunteers`
				},
				{
					number: submissionCount ?? undefined,
					title: 'submissions visible to you',
					link: `/venue/${venue.id}/submissions`
				},
				{ number: tokens?.length, title: 'tokens', link: `/venue/${venue.id}/transactions` }
			]}
		></Dashboard>

		<Subheader icon={ScholarLabel}>Submission types</Subheader>

		<p>
			These are the submission types for this venue. Each role can have a different amount of
			compensation for each type (e.g., reviews of new submissions may be compensated more than
			re-reviews).
		</p>

		{#if isAdmin}
			<Button
				tip="Add a submission type"
				action={() =>
					handle(db().createSubmissionType(venue.id, 'New type', 'New submission type', null))}
			>
				New submission type
			</Button>
		{/if}

		{#if types}
			<Table>
				{#snippet header()}
					<th>Type</th>
					<th>Description</th>
					<th>Revision of</th>
					{#if isAdmin && types.length > 1}<th></th>{/if}
				{/snippet}
				{#each types as type}
					<tr>
						<td>
							{#if isAdmin}
								<EditableText
									text={type.name}
									placeholder="Type name"
									edit={(text) => db().editSubmissionType(type.id, text, type.description, null)}
								/>
							{:else}
								<em>{type.name}</em>
							{/if}
						</td>
						<td>
							{#if isAdmin}
								<EditableText
									text={type.description}
									placeholder="Type description"
									inline={false}
									edit={(text) => db().editSubmissionType(type.id, type.name, text, null)}
								/>
							{:else}
								{type.description}
							{/if}
						</td>
						<td>
							{#if isAdmin}
								<Options
									options={[
										{ label: '—', value: undefined },
										...types
											.filter(
												(t) =>
													t.id !== type.id && !types.some((other) => other.revision_of === type.id)
											)
											.map((t) => ({ label: t.name, value: t.id }))
									]}
									value={type.revision_of ?? undefined}
									onChange={(value) =>
										db().editSubmissionType(type.id, type.name, type.description, value ?? null)}
								></Options>
							{:else}
								{types.find((t) => t.id === type.revision_of)?.name ?? '—'}
							{/if}
						</td>
						{#if isAdmin && types.length > 1}
							<td>
								<Button
									warn={ConfirmLabel}
									tip="Remove this submission type"
									action={() => handle(db().deleteSubmissionType(type.id))}
								>
									{DeleteLabel}
								</Button>
							</td>
						{/if}
					</tr>
				{/each}
			</Table>
		{:else}
			<Feedback error>Couldn't load venue's submission types.</Feedback>
		{/if}

		<Subheader id="roles" icon={ScholarLabel}>Roles</Subheader>

		{#if roles && currency}
			<p>See <Link to="/venue/{venue.id}/volunteers">all volunteers</Link> for this venue.</p>

			<Roles
				{venue}
				scholar={scholar?.id}
				{roles}
				{volunteers}
				isAdmin={false}
				{currency}
				{minters}
				{compensation}
				{types}
			/>

			{#if isVolunteer && scholar}
				<Form>
					<p>
						Are you <strong>missing compensation</strong> for a role you accepted? It's possible it hasn't
						been entered by the scholar responsible. You can request compensation for it here, and the
						scholar responsible will be notified.
					</p>

					<TextField
						label="Manuscript ID"
						placeholder="The ID associated with the manuscript in your reviewing system"
						bind:text={compensationManuscript}
					></TextField>
					<Options
						label="Role"
						options={roles.map((role) => ({
							label: role.name,
							value: role.id
						}))}
						bind:value={compensationRole}
					/>
					<TextField
						label="Note"
						placeholder="Message to the scholar responsible"
						bind:text={compensationNote}
					></TextField>
					<Button
						active={compensationManuscript.length > 0 && compensationRole.length > 0}
						tip="Request compensation"
						action={() =>
							handle(
								db().requestCompensation(
									scholar.id,
									venue.id,
									compensationManuscript,
									compensationRole,
									compensationNote
								)
							).then(() => {
								compensationManuscript = '';
								compensationRole = '';
								compensationNote = '';
								addFeedback('Compensation request sent.', 'success');
							})}>Request compensation</Button
					>
				</Form>
			{/if}
		{:else}
			<Feedback error>Couldn't load venue's roles.</Feedback>
		{/if}
	</Page>
{/if}
