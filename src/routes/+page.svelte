<script lang="ts">
	import Tip from '$lib/components/Tip.svelte';
	import Page from '$lib/components/Page.svelte';
	import { PUBLIC_ENV } from '$env/static/public';
	import Feedback from '$lib/components/Feedback.svelte';
	import { TokenLabel } from '$lib/components/Labels';
	import Text from '$lib/locales/Text.svelte';

	const inProd = PUBLIC_ENV === 'prod';
</script>

<Page icon={TokenLabel} title={(l) => l.page.home.title} breadcrumbs={[]}>
	{#snippet subtitle()}<Text path={(l) => l.page.home.lead} />{/snippet}

	<Text markdown path={(l) => l.page.home.call} />

	{#if !inProd}
		<Tip><Text markdown path={(l) => l.page.home.tip.browse} /></Tip>
		<Tip><Text markdown path={(l) => l.page.home.tip.track} /></Tip>

		<Tip><Text markdown path={(l) => l.page.home.tip.about} /></Tip>
	{:else}
		<Feedback text={(l) => l.page.home.feedback.beta}></Feedback>
	{/if}
</Page>
