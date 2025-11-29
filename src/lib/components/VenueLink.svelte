<script lang="ts">
	import { VenueLabel } from './Labels';
	import Link from './Link.svelte';

	interface Props {
		id: string;
		name: string;
	}

	let { id, name }: Props = $props();
</script>

<Link to="/venue/{id}" icon={VenueLabel}>{name}</Link>
