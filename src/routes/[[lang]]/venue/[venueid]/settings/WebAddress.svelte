<script lang="ts">
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { getDB } from '$lib/data/CRUD';
	import type { VenueRow } from '$data/types';
	import { slugifyTitle, validVenueSlug } from '$lib/validation';
	import { handle } from '$routes/feedback.svelte';

	let { venue }: { venue: VenueRow } = $props();

	const db = getDB();

	/** How long to wait after a keystroke before asking whether an address is free, so a
	 * name isn't a query per character. Matches ScholarSearch. */
	const DEBOUNCE_MS = 250;

	/** How the availability lookup stands. "Looked and found nobody" has to read differently
	 * from "haven't looked yet", which is otherwise the same empty space. */
	type Availability =
		| { status: 'idle' }
		| { status: 'checking' }
		| { status: 'free'; address: string }
		| { status: 'taken'; address: string };
	let availability = $state<Availability>({ status: 'idle' });

	/** What the field holds. Seeded from the venue's address, or from its title when it has
	 * none — an admin should start from a proposal rather than a blank box, and the title is
	 * almost always the right starting point. The proposal can still be invalid (a venue
	 * called "AI" has no four-character address in it), which the field says.
	 *
	 * A local working copy, like EditableText's: every write on this page ends in
	 * `invalidateAll()`, so saving the welcome amount would otherwise reset an address
	 * halfway typed. */
	// svelte-ignore state_referenced_locally
	let text = $state(venue.slug ?? slugifyTitle(venue.title));

	/** The address as of the last time it was taken. Plain `let`, not `$state`, so the
	 * effect below can write it without re-triggering itself. */
	// svelte-ignore state_referenced_locally
	let lastSlug = venue.slug;

	/** Take a new address only when the venue's own has genuinely changed — set from another
	 * session, or by the save below when the redirect doesn't remount this. */
	$effect(() => {
		if (venue.slug !== lastSlug) {
			lastSlug = venue.slug;
			text = venue.slug ?? '';
			availability = { status: 'idle' };
		}
	});

	let timer: ReturnType<typeof setTimeout> | undefined = undefined;
	/** Bumped per request, so a slow earlier lookup can't overwrite a later one when it
	 * finally lands. */
	let sequence = 0;

	const normalized = $derived(text.trim().toLowerCase());
	const wellFormed = $derived(validVenueSlug(normalized));
	const unchanged = $derived(normalized === venue.slug);

	/** Saving is refused for anything we already know is wrong. Not for `idle`, though: the
	 * check is a courtesy, and someone who types an address and hits the button before it
	 * returns should be allowed to — the unique index is what actually decides. */
	const saveable = $derived(wellFormed && !unchanged && availability.status !== 'taken');

	function check(value: string) {
		clearTimeout(timer);
		const candidate = value.trim().toLowerCase();
		// Nothing to ask about: malformed addresses can't be taken, and the address the
		// venue already holds is held by this venue.
		if (!validVenueSlug(candidate) || candidate === venue.slug) {
			sequence++;
			availability = { status: 'idle' };
			return;
		}
		timer = setTimeout(async () => {
			const mine = ++sequence;
			availability = { status: 'checking' };
			const { data } = await db().isVenueAddressAvailable(candidate);
			// Ignore a response that's already been typed past.
			if (sequence !== mine) return;
			availability = { status: data ? 'free' : 'taken', address: candidate };
		}, DEBOUNCE_MS);
	}

	async function save() {
		clearTimeout(timer);
		sequence++;
		if (await handle(db().editVenueSlug(venue.id, normalized))) {
			availability = { status: 'idle' };
			// The layout redirects the old address to the new one, so the page follows.
		}
	}

	$effect(() => () => clearTimeout(timer));
</script>

{#if venue.slug !== null}
	<Feedback
		inline={false}
		text={(l) => l.page.settings.feedback.addressCurrent}
		inputs={{ address: venue.slug }}
		testid="venue-address-current"
	/>
{/if}

<div class="address">
	<TextField
		bind:text
		strings={(l) => l.page.settings.field.webAddress}
		valid={(value) =>
			validVenueSlug(value.trim().toLowerCase())
				? undefined
				: (l) => l.page.settings.field.webAddress.invalid}
		change={check}
		testid="venue-address"
	/>
	<Button
		strings={venue.slug === null
			? (l) => l.page.settings.button.setWebAddress
			: (l) => l.page.settings.button.changeWebAddress}
		active={saveable}
		action={save}
		testid="venue-address-save"
	/>
</div>

{#if availability.status === 'checking'}
	<Feedback
		inline={false}
		text={(l) => l.page.settings.feedback.addressChecking}
		testid="venue-address-checking"
	/>
{:else if availability.status === 'free'}
	<Feedback
		inline={false}
		text={(l) => l.page.settings.feedback.addressAvailable}
		inputs={{ address: availability.address }}
		testid="venue-address-free"
	/>
{:else if availability.status === 'taken'}
	<Feedback
		warning
		inline={false}
		text={(l) => l.page.settings.feedback.addressTaken}
		inputs={{ address: availability.address }}
		testid="venue-address-taken"
	/>
{/if}

<style>
	.address {
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
		align-items: center;
		flex-wrap: wrap;
	}
</style>
