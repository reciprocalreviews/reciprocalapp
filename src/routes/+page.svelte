<script lang="ts">
	import { NEWSLETTER_URL } from '$lib/community';
	import Logo from '$lib/components/Logo.svelte';
	import Page from '$lib/components/Page.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import tokenChip from '$lib/components/tokenChip';
	import Text from '$lib/locales/Text.svelte';
	import { getLocaleContext } from '$routes/Contexts';

	const locale = getLocaleContext();
</script>

<Page title={(l) => l.page.home.title} breadcrumbs={[]}>
	{#snippet icon()}<Logo />{/snippet}

	<!-- The thesis the rest of the page argues for. It used to be the Page subtitle,
	     which the sticky header renders — where it sat beside the chrome rather than in
	     the argument, and stayed on screen long after it had been read. -->
	<p class="call-to-action"><Text path={(l) => l.page.home.lead} /></p>

	<Text
		markdown
		path={(l) => l.page.home.call}
		inputs={{ cost: tokenChip(locale().widget.tokens, 10) }}
	/>

	<Tip><Text markdown path={(l) => l.page.home.tip.browse} /></Tip>
	<Tip><Text markdown path={(l) => l.page.home.tip.track} /></Tip>
	<Tip>
		<Text markdown path={(l) => l.page.home.tip.about} inputs={{ newsletter: NEWSLETTER_URL }} />
	</Tip>
</Page>

<style>
	.call-to-action {
		font-family: 'Quicksand', sans-serif;
		font-size: var(--header-font-size);
		font-weight: 500;
		font-style: italic;
		text-align: inline-start;
		text-wrap: balance;
		margin: 0;
	}
</style>
