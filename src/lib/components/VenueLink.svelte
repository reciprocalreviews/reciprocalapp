<script lang="ts">
	import { VenueLabel } from './Labels';
	import Link from './Link.svelte';

	interface Props {
		id: string;
		name: string;
		/** The venue's web address, when the caller has it. Callers that only have an id
		 * still link correctly — the venue layout redirects an id to the address — so this
		 * is about which URL a reader sees, not whether the link works. */
		slug?: string | null;
		testid?: string;
		size?: 'small' | 'normal' | 'extra-small';
	}

	let { id, name, slug = null, testid, size = 'normal' }: Props = $props();
</script>

<Link to="/venue/{slug ?? id}" icon={VenueLabel} {testid} {size}>{name}</Link>
