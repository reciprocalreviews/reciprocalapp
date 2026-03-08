<script lang="ts">
	import { VenueLabel } from './Labels';
	import Link from './Link.svelte';

	interface Props {
		id: string;
		name: string;
		testid?: string;
		size?: 'small' | 'normal' | 'extra-small';
	}

	let { id, name, testid, size = 'normal' }: Props = $props();
</script>

<Link to="/venue/{id}" icon={VenueLabel} {testid} {size}>{name}</Link>
