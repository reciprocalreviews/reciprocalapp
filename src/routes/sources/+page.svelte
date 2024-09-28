<script lang="ts">
	import { goto } from '$app/navigation';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Link from '$lib/components/Link.svelte';
	import Loading from '$lib/components/Loading.svelte';
	import { getDB } from '$lib/data/Database';
	import { getAuth } from '../Auth.svelte';
	import Page from '$lib/components/Page.svelte';

	const db = getDB();
	const auth = getAuth();

	async function create() {
		const uid = auth.getUserID();
		if (uid === null) return;
		const source = await db.createSource({
			id: crypto.randomUUID(),
			name: '',
			short: '',
			link: '',
			archived: false,
			cost: {
				submit: 4,
				review: 1,
				meta: 1,
				edit: 0.1
			},
			editors: [uid],
			creationtime: Date.now(),
			expertise: []
		});
		goto(`/source/${source.id}`);
	}
</script>

<Page title="Venues">
	<h1>Venues</h1>

	<p>
		These are journals and conferences that are managing reviewers on this platform. Choose one to
		see it's policies or volunteer to review for it, or if you're an editor, create a new source.
	</p>

	{#if auth.isAuthenticated()}<Button tip="Create new venue" action={create}
			>+ create a new source</Button
		>{/if}

	{#await db.getSources()}
		<Loading />
	{:then sources}
		<ul>
			{#each sources.toSorted((a, b) => a.name.localeCompare(b.name)) as source}
				<li>
					<Link to="/source/{source.id}"
						>{#if source.name.length === 0}<em>Unnamed</em>{:else}{source.name}{/if}</Link
					>
				</li>
			{/each}
		</ul>
	{:catch}
		<Feedback>We couldn't load the sources.</Feedback>
	{/await}
</Page>
