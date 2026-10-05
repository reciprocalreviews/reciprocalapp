<script lang="ts">
	import type { VenueRow } from '$data/types';
	import Link from '#lib/components/Link.svelte';
	import Paragraph from '#lib/components/Paragraph.svelte';
	import ScholarLink from '#lib/components/ScholarLink.svelte';
	import { getDB } from '#lib/data/CRUD.js';
	import { venueBarName } from '#lib/data/venueBarLinks.js';

	let { venue }: { venue: VenueRow } = $props();

	const db = getDB();
</script>

<!-- Who answers for this venue. People wrote to the platform's stewards with questions only a
     venue's editors could answer, because nothing on the venue said who those were or how to
     reach them; the admins card is folded away under roles. An address appears only once
     verified, and scholars.email is already readable by anyone signed in. -->
<div class="contact" data-testid="venue-contact">
	<Paragraph
		text={(l) => l.page.venue.paragraph.questions}
		inputs={{ title: venueBarName(venue) }}
	/>
	<ul>
		{#each venue.admins as admin (admin)}
			<li>
				{#await db().getScholar(admin)}
					...
				{:then scholar}
					{#if scholar}
						<!-- The id-and-name form renders inline; a loaded Scholar renders a block,
						     which would push the address onto a line of its own. -->
						<ScholarLink id={{ id: scholar.getID(), name: scholar.getName() }} />
						{@const email = scholar.getEmail()}
						{#if email}
							· <Link to="mailto:{email}">{email}</Link>
						{/if}
					{/if}
				{/await}
			</li>
		{/each}
	</ul>
</div>
