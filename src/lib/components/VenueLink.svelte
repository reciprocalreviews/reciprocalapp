<script lang="ts">
	import Link from './Link.svelte';

	interface Props {
		id: string;
		name: string;
	}

	let { id, name }: Props = $props();
</script>

<Link to="/venue/{id}">{name}</Link>
