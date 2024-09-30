<script lang="ts">
	import Note from '$lib/components/Note.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import { getDB } from '$lib/data/Database';
	import type Scholar from '$lib/data/Scholar.svelte';

	let { scholar, editable }: { scholar: Scholar; editable: boolean } = $props();

	const anonymous = 'Anonymous';

	const db = getDB();

	async function update(text: string) {
		return await db.updateScholarName(scholar.getID(), text);
	}
</script>

<h1>
	{#if editable}<EditableText
			text={scholar.getName() ?? ''}
			label="name"
			placeholder="name"
			change="Change name"
			save="Save name"
			empty={anonymous}
			edit={update}
		/>{:else}{scholar.getName() ?? anonymous}{/if}
</h1>
Joined {new Date(scholar.getJoined()).toLocaleDateString()}
