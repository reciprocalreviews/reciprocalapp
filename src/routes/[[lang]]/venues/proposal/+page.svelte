<script lang="ts">
	import { goto } from '$app/navigation';
	import type { CurrencyID } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import { VenueLabel } from '$lib/components/Labels';
	import Options from '$lib/components/Options.svelte';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Status from '$lib/components/Status.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { parseAddresses } from '$lib/data/addresses';
	import { getDB } from '$lib/data/CRUD';
	import Text from '$lib/locales/Text.svelte';
	import { isntEmpty, validEmail, validEmails, validURL } from '$lib/validation';
	import { getAuth } from '$routes/Auth.svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import { handle } from '$routes/feedback.svelte';

	let { data } = $props();

	let currencies = $derived(data.currencies);

	let venue = $state('');
	let editors = $state('');
	let minters = $state('');
	let currency = $state<undefined | CurrencyID>(undefined);
	let url = $state('');
	let size = $state('');
	let message = $state('');
	let paymentFree = $state(false);
	let proposing = $state(false);

	const db = getDB();
	const auth = getAuth();
	const locale = getLocaleContext();

	function validSize(text: string) {
		return parseInt(text) > 0;
	}

	function validMessage(text: string) {
		return text.length > 0;
	}

	/** Addresses on the form that belong to no account yet, kept per field.
	 *
	 * Advisory only, deliberately. Approval takes whoever has an account: unlisted editors are
	 * emailed an invitation by this very proposal, and an unlisted minter means the approving
	 * steward holds the currency until the venue names someone. Blocking here would put the
	 * platform's hardest requirement at the moment a community is trying to join it. */
	let unknownEditors = $state<string[]>([]);
	let unknownMinters = $state<string[]>([]);

	/** Ask the database which of a field's addresses it doesn't know, once typing settles. */
	function checkAddresses(text: string, set: (unknown: string[]) => void) {
		const addresses = parseAddresses(text).filter(validEmail);
		clearTimeout(checking);
		checking = setTimeout(async () => {
			const { data } = await db().findUnknownAddresses(addresses);
			set(data ?? []);
		}, 400);
	}

	let checking: ReturnType<typeof setTimeout> | undefined;

	function editorsArentMinters() {
		if (currency !== undefined) return true;
		const editorsList = editors.split(',').map((e) => e.trim());
		const mintersList = minters.split(',').map((m) => m.trim());
		return editorsList.filter((value) => mintersList.includes(value)).length === 0;
	}

	async function propose() {
		const uid = auth().getUserID();
		if (
			!isntEmpty(venue) ||
			!validURL(url) ||
			!validEmails(editors, 1) ||
			(!paymentFree && currency === undefined && !validEmails(minters, 1)) ||
			!validSize(size) ||
			!validMessage(message) ||
			(!paymentFree && !editorsArentMinters()) ||
			uid === null
		)
			return;

		proposing = true;

		// `finally`, because the redirect below is not guaranteed to happen. A realtime
		// invalidation that lands while `goto` is loading takes over the navigation and
		// silently drops it — SvelteKit resolves the goto anyway and logs nothing — which
		// left this form disabled forever with the proposal already written and no way back
		// but a refresh. Clearing the flag regardless means the worst case is pressing
		// Propose twice, not a dead page.
		try {
			const proposalID = await handle(
				db().proposeVenue(
					uid,
					venue,
					url,
					parseAddresses(editors),
					paymentFree ? null : (currency ?? null),
					paymentFree || currency !== undefined ? [] : parseAddresses(minters),
					parseInt(size),
					message,
					paymentFree
				)
			);

			if (proposalID) await goto(`/venues/proposal/${proposalID}`);
		} finally {
			proposing = false;
		}
	}
</script>

<Page icon={VenueLabel} title={(l) => l.page.proposeVenue.title} breadcrumbs={[]}>
	<Paragraph text={(l) => l.page.proposeVenue.paragraph.reviewedBy} />
	<Paragraph text={(l) => l.page.proposeVenue.paragraph.howToPropose} />
	<Paragraph text={(l) => l.page.proposeVenue.paragraph.communitySupport} />
	<Paragraph text={(l) => l.page.proposeVenue.paragraph.emailNotice} />

	{#if auth().getUserID()}
		<Form>
			<section class="form-section">
				<p class="section-label"><Text path={(l) => l.page.proposeVenue.section.venueInfo} /></p>
				<TextField
					bind:text={venue}
					strings={(l) => l.page.proposeVenue.field.venueName}
					stretch
					valid={(text) =>
						text.length > 0 ? undefined : (l) => l.page.proposeVenue.field.venueName.invalid}
					testid="propose-venue-name"
				/>
				<TextField
					bind:text={url}
					strings={(l) => l.page.proposeVenue.field.url}
					active={!proposing}
					stretch
					valid={(text) =>
						validURL(text) ? undefined : (l) => l.page.proposeVenue.field.url.invalid}
					testid="propose-venue-url"
				/>
				<TextField
					bind:text={size}
					strings={(l) => l.page.proposeVenue.field.size}
					active={!proposing}
					stretch
					valid={(text) =>
						validSize(text) ? undefined : (l) => l.page.proposeVenue.field.size.invalid}
					testid="propose-venue-size"
				/>
			</section>

			<hr />

			<section class="form-section">
				<p class="section-label"><Text path={(l) => l.page.proposeVenue.section.team} /></p>
				<TextField
					bind:text={editors}
					strings={(l) => l.page.proposeVenue.field.editors}
					active={!proposing}
					stretch
					change={(text) => checkAddresses(text, (unknown) => (unknownEditors = unknown))}
					valid={(text) =>
						!validEmails(text, 1) ? (l) => l.page.proposeVenue.field.editors.invalid : undefined}
					testid="propose-venue-editors"
				/>
				{#if unknownEditors.length > 0}
					<Feedback
						warning
						inline={false}
						text={(l) => l.page.proposeVenue.field.editors.unknown}
						inputs={{ addresses: unknownEditors.join(', ') }}
						testid="propose-venue-editors-unknown"
					/>
				{/if}
				<Checkbox
					testid="propose-venue-payment-free"
					on={paymentFree}
					change={async (on) => {
						paymentFree = on;
						return {};
					}}
					label={(l) =>
						paymentFree
							? l.page.proposeVenue.checkbox.paymentFree.on
							: l.page.proposeVenue.checkbox.paymentFree.off}
				/>
				{#if !paymentFree}
					<Options
						strings={(l) => l.page.proposeVenue.options.currency}
						bind:value={currency}
						stretch
						options={[
							{ label: locale().page.proposeVenue.options.currency.createNew, value: undefined },
							...(currencies ?? []).map((currency) => ({
								label: currency.name,
								value: currency.id
							}))
						]}
					/>
					{#if currency === undefined}
						<TextField
							bind:text={minters}
							strings={(l) => l.page.proposeVenue.field.minters}
							active={!proposing}
							stretch
							change={(text) => checkAddresses(text, (unknown) => (unknownMinters = unknown))}
							valid={(text) =>
								!validEmails(text, 1)
									? (l) => l.page.proposeVenue.field.minters.invalid
									: !editorsArentMinters()
										? (l) => l.page.proposeVenue.field.mintersConflict
										: undefined}
							testid="propose-venue-minters"
						/>
						{#if unknownMinters.length > 0}
							<Feedback
								warning
								inline={false}
								text={(l) => l.page.proposeVenue.field.minters.unknown}
								inputs={{ addresses: unknownMinters.join(', ') }}
								testid="propose-venue-minters-unknown"
							/>
						{/if}
					{/if}
				{/if}
			</section>

			<hr />

			<section class="form-section">
				<p class="section-label"><Text path={(l) => l.page.proposeVenue.section.rationale} /></p>
				<TextField
					bind:text={message}
					strings={(l) => l.page.proposeVenue.field.rationale}
					inline={false}
					active={!proposing}
					stretch
					valid={(text) =>
						validMessage(text) ? undefined : (l) => l.page.proposeVenue.field.rationale.invalid}
					testid="propose-venue-rationale"
				/>
			</section>

			<hr />

			<div class="form-footer">
				<Button
					strings={(l) => l.page.proposeVenue.button.propose}
					action={propose}
					active={!proposing &&
						isntEmpty(venue) &&
						validURL(url) &&
						validEmails(editors, 1) &&
						(paymentFree || currency !== undefined || validEmails(minters, 1)) &&
						validSize(size) &&
						validMessage(message) &&
						(paymentFree || editorsArentMinters())}
					testid="propose-venue-submit"
				/>
			</div>
		</Form>
	{:else}
		<Status good={false} label={(l) => l.page.proposeVenue.status.notLoggedIn} />
	{/if}
</Page>

<style>
	.form-section {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
		width: 100%;
	}

	.section-label {
		font-size: var(--extra-small-font-size);
		font-weight: 600;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--inactive-color);
		margin: 0 0 var(--spacing-half);
	}

	.form-footer {
		display: flex;
		justify-content: flex-end;
		width: 100%;
	}
</style>
