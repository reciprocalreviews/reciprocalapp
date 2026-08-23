<script lang="ts">
	import { IdeaLabel } from '$lib/components/Labels';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import { articles } from './articles';
</script>

<Page icon={IdeaLabel} title={(l) => l.page.help.title} breadcrumbs={[]}>
	<Paragraph text={(l) => l.page.help.paragraph.intro} />

	<ul>
		{#each articles as article}
			<li>
				<Link to="/help/{article.slug}">{article.title}</Link>
				<div class="summary">{article.summary}</div>
			</li>
		{/each}
	</ul>

	<Paragraph text={(l) => l.page.help.paragraph.more} />
</Page>

<style>
	ul {
		padding-left: 1.5em;
	}

	li {
		margin-bottom: var(--spacing);
	}

	.summary {
		color: var(--inactive-color);
		font-size: var(--small-font-size);
	}
</style>
