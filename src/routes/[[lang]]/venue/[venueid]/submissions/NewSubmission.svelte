<script module lang="ts">
	type Charge = { scholar: string; payment: number };
</script>

<!-- svelte-ignore state_referenced_locally -->
<script lang="ts">
	import { goto } from '$app/navigation';
	import { venuePath } from '$lib/data/venuePath';
	import type { SubmissionType, SubmissionTypeID, VenueRow } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import Note from '$lib/components/Note.svelte';
	import Options from '$lib/components/Options.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import ScholarMatches from '$lib/components/ScholarMatches.svelte';
	import { ScholarSearch } from '$lib/components/ScholarSearch.svelte';
	import Slider from '$lib/components/Slider.svelte';
	import Table from '$lib/components/Table.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { getDB } from '$lib/data/CRUD';
	import type { ScholarMatch } from '$lib/data/SupabaseCRUD.svelte';
	import {
		duplicateScholars,
		validCharge,
		validCharges,
		validChargeFormat
	} from '$lib/data/charges';
	import type Locale from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';
	import { isntEmpty, validORCID } from '$lib/validation';
	import { getAuth } from '$routes/Auth.svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import { handle } from '$routes/feedback.svelte';

	let {
		venue,
		submissionTypes,
		priorSubmissions = [],
		initialManuscript = '',
		scholarORCID = null
	}: {
		venue: VenueRow;
		submissionTypes: SubmissionType[];
		/** Submissions in this venue the authenticated scholar authored, offered
		 * as on-platform predecessors to link a resubmission to (#124). The
		 * submission_type lets us auto-select the matching revision type. */
		priorSubmissions?: {
			id: string;
			externalid: string;
			title: string;
			submission_type: string;
		}[];
		/** Optional manuscript ID to pre-fill, e.g. from a `?manuscript=` query
		 * param when an editor's reviewing platform deep-links here. */
		initialManuscript?: string;
		/** The submitter's own ORCID, used to list them as the first author —
		 * unless they administer the venue, who start with an empty row. */
		scholarORCID?: string | null;
	} = $props();

	const db = getDB();
	const auth = getAuth();
	const locale = getLocaleContext();
	const user = $derived(auth().getUserID());

	/** The title of the submission we're adding */
	let title = $state('');
	let expertise = $state('');
	// svelte-ignore state_referenced_locally
	let externalID = $state(initialManuscript);
	let previousID = $state('');
	/** The on-platform predecessor selected from the picker, if any. */
	let previous = $state<string | null>(null);
	let submissionType = $state<SubmissionTypeID>(submissionTypes[0].id);
	let note = $state('');
	/** Who is signed in, read once at init: the two initialisers below have to
	 * settle the first author row before `user` is reactive. */
	// svelte-ignore state_referenced_locally
	const initialUser = auth().getUserID();
	/** Whether the person filling this in administers the venue, decided once at
	 * init for the pre-filled row below. `isAdmin` is the reactive form. */
	// svelte-ignore state_referenced_locally
	const initialAdmin = initialUser !== null && venue.admins.includes(initialUser);
	/** The submitter is listed as the first author, since for them a submission
	 * they are not an author of is refused anyway (RR009) and leaving the row
	 * blank made them type an identifier they may not have memorized. It starts
	 * resolved, too, rather than making them blur the field to see their own name.
	 *
	 * A venue admin is the exception, and gets an empty row: RR009 admits them
	 * precisely so they can record someone else's submission (DESIGN's manual
	 * add), so the premise above does not hold for them, and an editor who did
	 * not notice the prefill would be recorded as a non-paying co-author of a
	 * paper they did not write — which is what conflict-of-interest checks read
	 * and what the author-list lock protects. An admin submitting their own
	 * paper names themselves the same way they name any co-author. */
	// svelte-ignore state_referenced_locally
	let charges = $state<Charge[]>([
		{ scholar: initialAdmin ? '' : (scholarORCID ?? ''), payment: 0 }
	]);

	/** The selected submission type, whose cost the author pays. */
	let selectedType = $derived(submissionTypes.find((t) => t.id === submissionType));

	/** The cost to submit is the selected submission type's cost. */
	let cost = $derived(selectedType?.submission_cost ?? 0);

	/** When false, the venue is payment-free: hide cost/payment/balance UI and
	 * skip the balance check. Authors may still be listed (payment forced to 0). */
	let showPayment = $derived(!venue.payment_free);

	/** The revision type whose `revision_of` points at the given type, if any.
	 * Used to auto-select the right type when linking a predecessor. */
	function revisionTypeFor(typeID: SubmissionTypeID): SubmissionTypeID | undefined {
		return submissionTypes.find((t) => t.revision_of === typeID)?.id;
	}

	/** Per-row ORCID lookup and name search. One instance per author row; see
	 * ScholarSearch.svelte.ts for why the behaviour is a class rather than a
	 * component (the field and its matches live in different table cells). */
	let searches = $state<ScholarSearch[]>([
		new ScholarSearch(
			db,
			!initialAdmin && scholarORCID !== null && initialUser !== null ? initialUser : undefined
		)
	]);

	/** Adopt a searched-for scholar: their ORCID becomes the row's value, and
	 * the row is already resolved, so no lookup round trip is needed. */
	function chooseMatch(index: number, match: ScholarMatch) {
		if (match.orcid === null) return;
		charges[index].scholar = match.orcid;
		searches[index].choose(match);
	}

	/** True when this row names a scholar an earlier row already named. The
	 * global "Authors must be unique" feedback says that it happened; this says
	 * which row, which matters more now that row one is pre-filled and adding
	 * yourself again is the easy mistake. */
	function isDuplicateRow(index: number): boolean {
		const mine = charges[index].scholar.trim().toLowerCase();
		if (mine === '') return false;
		return charges.some((c, i) => i < index && c.scholar.trim().toLowerCase() === mine);
	}

	/** True if the specified charges can be afforded, undefined if checking, string describing the problem. */
	let affordable = $state<((l: Locale) => string) | undefined | true>(undefined);

	/** When any charge's payment or scholar changes, reset affordable */
	$effect(() => {
		charges.forEach((c) => {
			c.payment;
			c.scholar;
		});
		affordable = undefined;
	});

	/** Whether the authenticated user administers this venue. */
	let isAdmin = $derived(user !== null && venue.admins.includes(user));

	/** True if the authenticated user is neither one of the found authors nor an
	 * admin of this venue — the two callers `create_submission` admits (RR009).
	 * An admin is exempt because recording a submission for its authors is a
	 * documented editor power; without the exemption the form dead-ended on the
	 * one path it exists to serve (#153). */
	let isNonAuthor = $derived(
		!isAdmin && searches.some((s) => s.id !== undefined) && !searches.some((s) => s.id === user)
	);

	function validExternalID(id: string) {
		return id.length > 0;
	}

	async function checkAffordability() {
		affordable = undefined;
		const { data, error } = await db().verifyCharges(charges, venue.currency);

		if (error) affordable = () => error.message;
		else if (data === undefined) {
			affordable = (l) => l.page.newSubmission.error.balanceCheck;
		} else if (data !== true) {
			const notFound = data
				.filter((result) => result.covered === undefined)
				.map((result) => result.scholar);
			const short = data
				.filter((result) => result.covered === false)
				.map((result) => result.scholar);
			if (notFound.length > 0)
				affordable = (l) =>
					l.page.newSubmission.error.notFound.replace('{scholars}', notFound.join(', '));
			else if (short.length > 0)
				affordable = (l) =>
					l.page.newSubmission.error.insufficentFunds.replace('{short}', short.join(', '));
		} else {
			affordable = true;
		}
	}

	function validSubmission(title: string, externalID: string, charges: Charge[], cost: number) {
		return (
			isntEmpty(title) &&
			validExternalID(externalID) &&
			(previousID.length === 0 || validExternalID(previousID)) &&
			validCharges(charges, cost)
		);
	}

	/** Whether the submission can be created. In a payment-free venue there is
	 * no balance to verify, so the charges are checked against a cost of zero —
	 * which still rejects a malformed ORCID or the same author listed twice, both
	 * of which the database now refuses (RR008). Either way the caller must be an
	 * author or a venue admin: the balance check gated that before, so it did not
	 * hold in a payment-free venue, where there is no balance check to reach. */
	let canSubmit = $derived(
		!isNonAuthor &&
			(venue.payment_free
				? isntEmpty(title) &&
					validExternalID(externalID) &&
					(previousID.length === 0 || validExternalID(previousID)) &&
					validCharges(charges, 0)
				: affordable === true && validSubmission(title, externalID, charges, cost))
	);
</script>

{#if !user}
	<Feedback error text={(l) => l.page.newSubmission.feedback.notLoggedIn} />
{:else}
	<Paragraph text={(l) => l.page.newSubmission.paragraph.intro} />

	<Form>
		<h3><Text path={(l) => l.page.newSubmission.header.details} /></h3>
		<TextField
			strings={(l) => l.page.submissions.field.title}
			size={40}
			bind:text={title}
			valid={(text) =>
				isntEmpty(text) ? undefined : (l) => l.page.submissions.field.title.invalid}
			testid="submission-title"
		/>
		<TextField
			strings={(l) => l.page.submissions.field.expertise}
			size={40}
			bind:text={expertise}
		/>
		<TextField
			strings={(l) => l.page.submissions.field.manuscriptID}
			size={40}
			bind:text={externalID}
			valid={(text) =>
				validExternalID(text) ? undefined : (l) => l.page.submissions.field.manuscriptID.invalid}
			testid="submission-manuscript-id"
		/>
		{#if priorSubmissions.length > 0}
			<Options
				strings={(l) => l.page.newSubmission.options.previous}
				options={[
					{ label: locale().shorthand.empty, value: undefined },
					...priorSubmissions.map((s) => ({
						label: s.title.trim().length > 0 ? `${s.externalid} — ${s.title}` : s.externalid,
						value: s.id
					}))
				]}
				value={previous ?? undefined}
				onChange={(value) => {
					previous = value ?? null;
					const chosen = value ? priorSubmissions.find((s) => s.id === value) : undefined;
					// Mirror the chosen predecessor's external ID into the (now
					// locked) free-text field; clear it when deselected.
					previousID = chosen?.externalid ?? '';
					// Auto-select the revision type of the predecessor's type, so
					// the right cost and compensation apply.
					if (chosen) {
						const revision = revisionTypeFor(chosen.submission_type);
						if (revision) submissionType = revision;
					}
				}}
			></Options>
		{/if}
		<TextField
			strings={(l) => l.page.submissions.field.previousID}
			size={40}
			active={previous === null}
			bind:text={previousID}
			done={() => {
				// Best-effort: if a typed external ID matches one of the author's
				// own prior submissions, auto-select that type's revision type.
				const match = priorSubmissions.find((s) => s.externalid === previousID.trim());
				if (match) {
					const revision = revisionTypeFor(match.submission_type);
					if (revision) submissionType = revision;
				}
			}}
			testid="submission-previous-id"
		/>
		<Options
			strings={(l) => l.page.newSubmission.options.submissionType}
			bind:value={submissionType}
			options={submissionTypes.map((type) => ({ value: type.id, label: type.name }))}
		></Options>
		<TextField strings={(l) => l.page.submissions.field.note} size={60} bind:text={note} />

		{#if showPayment}
			<h3><Text path={(l) => l.page.newSubmission.header.payment} /></h3>
			<Note path={(l) => l.page.newSubmission.note.payment} />
			<Feedback
				text={(l) =>
					l.page.newSubmission.cost
						.replaceAll('{type}', selectedType?.name ?? '')
						.replaceAll('{cost}', cost.toString())}
			/>
		{:else}
			<h3><Text path={(l) => l.page.newSubmission.header.authors} /></h3>
			<Note path={(l) => l.page.newSubmission.note.authors} />
		{/if}
		{#if isAdmin}
			<Note path={(l) => l.page.newSubmission.note.onBehalf} />
		{/if}
		<Table>
			{#snippet header()}
				<th><Text path={(l) => l.page.newSubmission.table.orcid} /></th>
				<th><Text path={(l) => l.page.newSubmission.table.name} /></th>
				{#if showPayment}<th><Text path={(l) => l.page.newSubmission.table.payment} /></th>{/if}
				<th><Text path={(l) => l.page.newSubmission.table.removeAuthor} /></th>
			{/snippet}
			{#each charges as charge, index}
				<tr class="charge">
					<td>
						<TextField
							strings={(l) => ({ ...l.page.newSubmission.field.authorOrcid, label: undefined })}
							size={24}
							bind:text={charge.scholar}
							valid={(text) => {
								if (!validORCID(text))
									return (l) => l.page.newSubmission.field.authorOrcid.invalid ?? '';
								if (isDuplicateRow(index))
									return (l) => l.page.newSubmission.field.authorOrcid.duplicate;
								if (searches[index]?.notFound)
									return (l) => l.page.newSubmission.field.authorOrcid.unknownScholar;
								return undefined;
							}}
							done={() => searches[index].done(charge.scholar)}
							change={(text) => searches[index].change(text)}
							testid="author-orcid-{index}"
						/>
					</td>
					<td class="scholar-name">
						<ScholarMatches
							search={searches[index]}
							choose={(match) => chooseMatch(index, match)}
							placeholder="—"
							foundTestid="scholar-found-{index}"
							matchTestid="author-match-{index}"
							noMatchesTestid="author-no-matches-{index}"
						/>
					</td>
					{#if showPayment}
						<td
							><Slider
								strings={(l) => ({ ...l.page.newSubmission.slider.payment, label: undefined })}
								bind:value={charge.payment}
								min={0}
								max={cost}
								step={1}
								testid="payment-slider-{index}"
							/></td
						>
					{/if}
					<td
						><Button
							strings={(l) => l.page.newSubmission.button.removeAuthor}
							active={charges.length > 1}
							action={() => {
								charges.splice(index, 1);
								searches.splice(index, 1)[0]?.dispose();
							}}
						/>
					</td>
				</tr>
			{/each}
		</Table>

		<Button
			strings={(l) => l.page.newSubmission.button.addAuthor}
			testid="add-author"
			action={() => {
				charges.push({ scholar: '', payment: 0 });
				searches.push(new ScholarSearch(db));
			}}
		/>

		{#if duplicateScholars(charges)}
			<Feedback error text={(l) => l.page.newSubmission.feedback.duplicateScholars}></Feedback>
		{:else if isNonAuthor}
			<Feedback error text={(l) => l.page.newSubmission.feedback.onlyAuthors} />
		{:else if !showPayment}
			<!-- Payment-free venue: no balance to verify. -->
		{:else if charges.reduce((sum, charge) => sum + charge.payment, 0) < cost}
			<Feedback
				error
				text={(l) =>
					l.page.newSubmission.feedback.incompletePayment.replace(
						'{deficit}',
						(cost - charges.reduce((sum, charge) => sum + charge.payment, 0)).toString()
					)}
			/>
		{:else}
			<Note path={(l) => l.page.newSubmission.note.balance} />

			<Button
				strings={(l) => l.page.newSubmission.button.checkBalances}
				testid="check-balances"
				active={validChargeFormat(charges) && validCharge(charges, cost) && affordable !== true}
				action={checkAffordability}
			/>

			{#if typeof affordable === 'function'}
				<Feedback error text={affordable} />
				<!-- A failed balance check is a dead end without this: volunteering
				     to review is how a scholar earns the tokens to submit. -->
				<Paragraph
					text={(l) => l.page.newSubmission.note.earnTokens}
					inputs={{ venue: `/venue/${venuePath(venue)}` }}
				/>
			{:else if affordable === true}
				<Feedback text={(l) => l.page.newSubmission.feedback.sufficientBalance} />
			{/if}
		{/if}

		<h3><Text path={(l) => l.page.newSubmission.header.submit} /></h3>

		{#if showPayment}
			<Note path={(l) => l.page.newSubmission.note.approve} />
		{/if}

		<Button
			strings={(l) => l.page.newSubmission.button.submit}
			testid="submit-submission"
			active={canSubmit}
			action={async () => {
				if (user) {
					// In a payment-free venue, drop any blank author rows so an
					// authorless submission is allowed (verifyCharges needs no charges).
					const submitCharges = venue.payment_free
						? charges.filter((c) => c.scholar.trim() !== '')
						: charges;
					const result = await handle(
						db().createSubmission(
							user,
							title,
							expertise,
							venue.id,
							externalID,
							previousID.trim() === '' ? null : previousID.trim(),
							previous,
							submissionType,
							submitCharges,
							note.trim() === '' ? null : note.trim()
						)
					);

					// Redirect to the submission page if successful.
					if (result) {
						goto(`/venue/${venuePath(venue)}/submission/${result}`);
					}

					return result;
				}
			}}
		/>
	</Form>
{/if}

<style>
	.charge td {
		vertical-align: baseline;
	}
</style>
