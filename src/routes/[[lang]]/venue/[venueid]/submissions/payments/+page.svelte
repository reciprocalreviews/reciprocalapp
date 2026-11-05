<script lang="ts">
	import Button from '#lib/components/Button.svelte';
	import CopyButton from '#lib/components/CopyButton.svelte';
	import Feedback from '#lib/components/Feedback.svelte';
	import Form from '#lib/components/Form.svelte';
	import Link from '#lib/components/Link.svelte';
	import Page from '#lib/components/Page.svelte';
	import Paragraph from '#lib/components/Paragraph.svelte';
	import ScholarLink from '#lib/components/ScholarLink.svelte';
	import Status from '#lib/components/Status.svelte';
	import SubmissionLink from '#lib/components/SubmissionLink.svelte';
	import Table from '#lib/components/Table.svelte';
	import TextField from '#lib/components/TextField.svelte';
	import { getDB, type SubmissionPayments } from '#lib/data/CRUD.js';
	import {
		checkPayments,
		parseManuscriptIDs,
		type AuthorCharge,
		type PaymentCheck,
		type PaymentCheckState
	} from '#lib/data/submissionPayment.js';
	import { venueBarName } from '#lib/data/venueBarLinks.js';
	import type LocaleText from '#lib/locales/Locale.js';
	import Text from '#lib/locales/Text.svelte';
	import { handle } from '#routes/feedback.svelte.js';
	import { type PageData } from './$types';

	/** Takes manuscript IDs pasted from the venue's reviewing system and says, for each,
	 * whether it has been paid for here and who to write to if not. The answer is local
	 * state rather than page data, so a realtime refresh doesn't clear it mid-read. */
	let { data }: { data: PageData } = $props();
	const { venue, isAdmin } = $derived(data);

	const db = getDB();

	let text = $state('');
	const ids = $derived(parseManuscriptIDs(text));

	/** The last check's result, or null before the first. */
	let checks = $state<PaymentCheck[] | null>(null);
	let authors = $state<Map<string, SubmissionPayments['authors'][number]>>(new Map());

	async function check() {
		if (venue === null) return;
		// Inactive with nothing to check, so there is always at least one ID.
		const requested = ids;
		const result = await handle(db().getSubmissionPayments(venue.id, requested));
		if (typeof result !== 'object' || result === null) return;
		authors = new Map(result.authors.map((a) => [a.id, a]));
		checks = checkPayments(
			requested,
			result.submissions,
			new Map(result.transactions.map((t) => [t.id, t.status]))
		);
	}

	const counts = $derived.by(() => {
		const tally: Record<PaymentCheckState, number> = {
			missing: 0,
			outstanding: 0,
			imported: 0,
			paid: 0,
			free: 0
		};
		for (const c of checks ?? []) tally[c.state]++;
		return tally;
	});

	/** Every address to write to, once each, in the order the rows list them. Authors with
	 * no contact email are left out; their rows say so. */
	const emails = $derived([
		...new Set(
			(checks ?? []).flatMap((c) =>
				c.state === 'outstanding'
					? c.unsettled.flatMap((charge) => authors.get(charge.author)?.email ?? [])
					: []
			)
		)
	]);

	/** Paid is the one good answer; free and imported are facts rather than verdicts. */
	const tone: Record<PaymentCheckState, { good: boolean; neutral: boolean }> = {
		missing: { good: false, neutral: false },
		outstanding: { good: false, neutral: false },
		imported: { good: false, neutral: true },
		paid: { good: true, neutral: false },
		free: { good: false, neutral: true }
	};

	function chargeNote(charge: AuthorCharge): (l: LocaleText) => string {
		return (l) =>
			l.page.submissionPayments.contact[charge.status === 'approved' ? 'unknown' : charge.status];
	}
</script>

{#if venue === null}
	<Page title={(l) => l.page.submissionPayments.title}>
		<Feedback error text={(l) => l.page.submissionPayments.notLoaded} />
	</Page>
{:else}
	<Page title={(l) => l.page.submissionPayments.title} context={venueBarName(venue)}>
		{#if !isAdmin}
			<Feedback
				error
				text={(l) => l.page.submissionPayments.notAdmin}
				testid="payments-not-admin"
			/>
		{:else if venue.payment_free}
			<Feedback text={(l) => l.page.submissionPayments.paymentFree} />
		{:else}
			<Paragraph text={(l) => l.page.submissionPayments.intro} />
			<Form>
				<!-- Capped, because the textarea grows to its content and a pasted list can
				     run to hundreds of lines. -->
				<div class="paste">
					<TextField
						strings={(l) => l.page.submissionPayments.field.ids}
						size={40}
						inline={false}
						testid="payments-ids"
						bind:text
					/>
				</div>
				<Button
					strings={(l) => l.page.submissionPayments.button.check}
					type="submit"
					active={ids.length > 0}
					action={check}
					testid="payments-check"
				/>
			</Form>

			{#if checks !== null}
				<p data-testid="payments-summary">
					<Text
						path={(l) => l.page.submissionPayments.summary}
						inputs={{
							count: checks.length.toString(),
							missing: counts.missing.toString(),
							outstanding: counts.outstanding.toString(),
							imported: counts.imported.toString(),
							paid: counts.paid.toString(),
							free: counts.free.toString()
						}}
					/>
				</p>
				{#if emails.length > 0}
					<CopyButton
						text={emails.join(', ')}
						strings={(l) => l.page.submissionPayments.button.copyEmails}
						testid="payments-copy-emails"
					/>
				{/if}
				<Table full>
					{#snippet header()}
						<th><Text path={(l) => l.page.submissionPayments.headers.id} /></th>
						<th><Text path={(l) => l.page.submissionPayments.headers.submission} /></th>
						<th><Text path={(l) => l.page.submissionPayments.headers.status} /></th>
						<th><Text path={(l) => l.page.submissionPayments.headers.contact} /></th>
					{/snippet}
					{#each checks as c, index (c.externalid)}
						<tr data-testid="payments-row-{index}">
							<td class="id" data-testid="payments-row-{index}-id">{c.externalid}</td>
							<td>
								{#if c.state !== 'missing'}
									<SubmissionLink submission={c.submission} venueSlug={venue.slug} />
								{/if}
							</td>
							<td>
								<Status
									good={tone[c.state].good}
									neutral={tone[c.state].neutral}
									label={(l) => l.page.submissionPayments.status[c.state]}
									testid="payments-row-{index}-status"
								/>
							</td>
							<td data-testid="payments-row-{index}-contact">
								{#if c.state === 'missing' || c.state === 'imported'}
									<Text path={(l) => l.page.submissionPayments.contact[c.state]} />
								{:else if c.state === 'outstanding'}
									<ul>
										{#each c.unsettled as charge (charge.author)}
											{@const author = authors.get(charge.author)}
											<li>
												<ScholarLink
													id={author ? { id: author.id, name: author.name } : charge.author}
												/>
												·
												{#if author?.email}<Link to="mailto:{author.email}">{author.email}</Link
													>{:else}<Text
														path={(l) => l.page.submissionPayments.contact.noEmail}
													/>{/if}
												· <Text path={chargeNote(charge)} />
											</li>
										{/each}
									</ul>
								{/if}
							</td>
						</tr>
					{/each}
				</Table>
			{/if}
		{/if}
	</Page>
{/if}

<style>
	.paste :global(textarea) {
		max-height: 12em;
		overflow-y: auto;
	}

	/* A manuscript ID is one token: broken at its hyphens it no longer reads as one. */
	.id {
		white-space: nowrap;
	}

	ul {
		margin: 0;
		padding-left: 1em;
	}
</style>
