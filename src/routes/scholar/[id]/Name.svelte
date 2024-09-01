<script lang="ts">
	import Link from '$lib/components/Link.svelte';
	import Note from '$lib/components/Note.svelte';
	import type { Scholar } from '../../../data/types';
	import Button from '$lib/components/Button.svelte';

	let { scholar, editable }: { scholar: Scholar; editable: boolean } = $props();

	let editingName = $state(false);
</script>

<h1>
	{#if editable && editingName}{:else if scholar.name === null}<em>Anonymous</em
		>{:else}{scholar.name}{/if}{#if editable}
		<Button action={() => {}}>✎</Button>{/if}
</h1>
<Note>Joined {new Date(scholar.when).toLocaleDateString()}</Note>
<p><Link to="https://orcid.org/{scholar.orcid}">ORCID Profile</Link></p>
