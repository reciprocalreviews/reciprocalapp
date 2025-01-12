<script lang="ts">
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Link from '$lib/components/Link.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import { getDB } from '$lib/data/CRUD';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { ORCIDRegex } from '../../../data/ORCID';
	import Page from '$lib/components/Page.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Card from '$lib/components/Card.svelte';
	import Note from '$lib/components/Note.svelte';
	import { DeleteLabel } from '$lib/components/Labels';
	import { validIdentifier, validURL, validEmail, validInteger } from '$lib/validation';
	import { handle } from '../../feedback.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import Roles from './Roles.svelte';
	import type { PageData } from './$types';
	import Gift from '$lib/components/Gift.svelte';

	let { data }: { data: PageData } = $props();
	const { venue, currency, scholar, roles, commitments, tokens, transactions } = $derived(data);

	const db = getDB();
	let editor = $derived(scholar && venue && venue.editors.includes(scholar.id));

	let newEditor: string = $state('');
</script>

{#if venue === null}
	<Page title="Unknown venue">
		<p>Unable to find this venue.</p>
	</Page>
{:else}
	<Page title={venue.title}>
		{#snippet subtitle()}Venue{/snippet}
		{#snippet details()}<Link to={venue.url}>{venue.url}</Link>{/snippet}
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

		<!-- Key details about costs. -->
		<p>
			{#if currency}
				This venue uses the <Link to="/currency/{venue.currency}">{currency.name}</Link> currency.
			{:else}
				<Feedback error>Unable to load this venue's currency.</Feedback>
			{/if}
			New volunteers receive <Tokens amount={venue.welcome_amount}></Tokens> when they volunteer to review.
			New submissions cost <Tokens amount={venue.submission_cost}></Tokens>.
		</p>

		<!-- Show metadata -->
		<Cards>
			<Card
				expand
				icon={venue.editors.length}
				header="editors"
				note="Give and take tokens for reviewing"
			>
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
					<Note>
						Editors can edit venue information, add and remove other editors, create and archive
						submissions, and gift review tokens. They are typically Editors-in-Chief of a journal or
						Program Chairs of a conference.
					</Note>
				{/if}
			</Card>
		</Cards>

		<h2>Volunteer</h2>
		<p>See <Link to="/venue/{venue.id}/volunteers">all volunteers</Link> for this venue.</p>

		<Cards>
			{#if roles}
				{#each roles as role (role.id)}
					{@const commitment = commitments?.find((c) => c.roleid === role.id)}
					<Card
						full
						icon={role.amount}
						header={role.name}
						note={role.description}
						group="invite only"
					>
						<div class="role">
							<div class="tags">
								{#if scholar && !role.invited && commitment === undefined}
									<Button
										tip="Volunteer for this role"
										action={() =>
											handle(
												db.createVolunteer(scholar.id, role.id, true, true),
												'Thank you for volunteering! The minter will approve your welcome tokens soon.'
											)}>Volunteer …</Button
									>
								{/if}
							</div>
							<Note
								>{#if role.description.length > 0}{role.description}{:else}<em>No description.</em
									>{/if}</Note
							>

							{#if commitment}
								<hr />
								{#if role.invited && commitment.accepted === 'invited'}
									<p>
										The editor has invited you to take this role. <Button
											tip="accept this invitation"
											action={() => handle(db.acceptRoleInvite(commitment.id, 'accepted'))}
											>Accept</Button
										><Button
											tip="decline this invitation"
											action={() => handle(db.acceptRoleInvite(commitment.id, 'declined'))}
											>Decline</Button
										>
									</p>
								{/if}
								{#if commitment.accepted === 'accepted'}
									{#if commitment.active}
										<p>
											Thanks for volunteering for this role! <Button
												tip="Stop volunteering"
												action={() => handle(db.updateVolunteerActive(commitment.id, false))}
												>Stop...</Button
											>
										</p>
										<EditableText
											text={commitment.expertise}
											label="what is your expertise (separated by commas)?"
											placeholder="topic, area, method, theory, etc."
											edit={(text) => db.updateVolunteerExpertise(commitment.id, text)}
										/>
									{:else}
										<p>
											You stopped volunteering for this role. <Button
												tip="Resume volunteering"
												action={() => handle(db.updateVolunteerActive(commitment.id, true))}
												>Resume...</Button
											>
										</p>{/if}
								{:else if commitment.accepted === 'declined'}
									<p>
										You declined this role. Would you like to accept it?
										<Button
											tip="accept this invitation"
											action={() => handle(db.acceptRoleInvite(commitment.id, 'accepted'))}
											>Accept</Button
										>
									</p>
								{/if}
							{/if}
						</div>
					</Card>
				{:else}
					<Feedback>This venue has no volunteer roles.</Feedback>
				{/each}
			{:else}
				<Feedback error>Couldn't load venue's roles.</Feedback>
			{/if}
		</Cards>

		{#if editor}
			<h2>Editor's corner</h2>
			<Cards>
				<Card group="editors" icon={tokens ?? 0} header="tokens" note="balance and gifts">
					<p>
						This venue currently has {#if tokens !== null}<Tokens amount={tokens}></Tokens>{:else}an
							unknown number of{/if} tokens and is involved in {#if transactions !== null}<strong
								>{transactions}</strong
							>{:else}an unknown number of{/if} transactions.
						<Link to="/venue/{venue.id}/transactions">See all transactions</Link>.
					</p>

					{#if scholar}
						<Gift
							max={tokens}
							purpose="Venue gift to scholar"
							success="Your tokens were successfully gifted."
							transfer={(giftRecipient: string, giftAmount: number, purpose: string) =>
								scholar
									? db.transferTokens(
											scholar.id,
											venue.id,
											'venueid',
											giftRecipient,
											'emailorcid',
											giftAmount,
											purpose
										)
									: undefined}
						/>
					{/if}
				</Card>
				<Card full group="editors" icon={roles?.length ?? 0} header="roles" note="The venue's jobs">
					<p>
						These are the roles that volunteers can commit to. Create roles such as <em>reviewer</em
						>,
						<em>program commitee</em>, <em>associate editor</em> to represent the different kinds of
						contributions volunteers can make to this venue.
					</p>

					<h3>Roles</h3>
					<Roles {venue} {roles} />
				</Card>
				<Card group="editors" icon="⛭" header="settings" note="Update title, url, costs, etc.">
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
						placeholder="e.g., 40"
						valid={validInteger}
						edit={(text) => db.editVenueWelcomeAmount(venue.id, parseInt(text))}
					/>
					<EditableText
						text={venue.submission_cost.toString()}
						label="Submission cost"
						placeholder="e.g., 40"
						valid={validInteger}
						edit={(text) => db.editVenueSubmissionCost(venue.id, parseInt(text))}
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
			</Cards>
		{/if}
	</Page>
{/if}

<style>
	.role {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
	}
</style>
