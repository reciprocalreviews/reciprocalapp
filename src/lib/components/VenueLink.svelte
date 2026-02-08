<script lang="ts">
	import { VenueLabel } from './Labels';
	import Link from './Link.svelte';

	interface Props {
		id: string;
		name: string;
		testid?: string;
	}

	let { id, name, testid }: Props = $props();
</script>

<Link to="/venue/{id}" icon={VenueLabel} {testid}>{name}</Link>
