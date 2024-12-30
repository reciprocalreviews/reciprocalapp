<script lang="ts">
	import { getDB } from '$lib/data/CRUD';
	import Link from './Link.svelte';

	interface Props {
		id: string;
		name: string;
	}

	let { id, name }: Props = $props();

	const db = getDB();
</script>

<Link to="/venue/{id}">{name}</Link>
