<script lang="ts">
	import ContextBar from '#lib/components/ContextBar.svelte';
	import { VenueLabel } from '#lib/components/Labels.js';
	import { venueBarLinks, venueBarName, type VenueBarVenue } from '#lib/data/venueBarLinks.js';
	import { venuePath } from '#lib/data/venuePath.js';
	import { getLocaleContext } from '$routes/Contexts';

	/**
	 * The venue's own band of chrome, on every route inside it.
	 *
	 * It replaced the per-page title band, which spent a full band of the viewport saying
	 * the venue's name and then, underneath, the name of the section just clicked (#176).
	 * In the same space this names the venue AND reaches the five places inside it people
	 * actually go, which used to be two or three clicks deep. Every other area now has a
	 * bar like it; this is the one with rules of its own.
	 *
	 * Which links appear is decided by `venueBarLinks`, not here: the gates it applies
	 * (payment-free, admin-only, no website) are rules, and rules in this codebase live in
	 * modules where a unit test can reach them.
	 */
	let {
		venue,
		scholarID,
		inactive = false
	}: {
		venue: VenueBarVenue;
		/** The signed-in scholar, or null when anonymous. Decides whether Settings shows. */
		scholarID: string | null;
		/** Whether the venue is inactive. Only admins get this far into an inactive venue,
		 * but the chip checks anyway, since it links to a page only they can open. */
		inactive?: boolean;
	} = $props();

	const locale = getLocaleContext();

	const home = $derived(`/venue/${venuePath(venue)}`);
	/** The short name, which is what the bar's name is for: "ToK" fits where "Transactions
	 * on Knowledge" does not, and the landing page still spells the full title out. */
	const bar = $derived({
		icon: VenueLabel,
		name: venueBarName(venue),
		href: home,
		links: venueBarLinks(venue, scholarID, locale())
	});
	const showInactive = $derived(inactive && scholarID !== null && venue.admins.includes(scholarID));
</script>

<ContextBar
	{bar}
	menu={(l) => l.page.venue.bar.menu}
	testid="venue-bar"
	menuTestid="venue-menu"
	chip={showInactive
		? {
				label: locale().page.venue.bar.inactive.label,
				tip: locale().page.venue.bar.inactive.tip,
				href: `${home}/settings`,
				testid: 'venue-bar-inactive'
			}
		: undefined}
/>
