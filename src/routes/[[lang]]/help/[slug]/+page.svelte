<script lang="ts">
	import { IdeaLabel } from '$lib/components/Labels';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import { marked } from 'marked';

	let { data } = $props();
	let { article } = $derived(data);

	// Article bodies are authored in this repository, not submitted by anyone, so the
	// rendered HTML is as trusted as the rest of the source. The leading `# Title` is
	// dropped because Page already renders the title as the page heading.
	let html = $derived(marked(article.body.replace(/^#\s.*\n/, '')) as string);
</script>

<Page icon={IdeaLabel} title={article.title} breadcrumbs={[['/help', 'Help']]}>
	<div class="article">
		{@html html}
	</div>

	<Paragraph text={(l) => l.page.help.paragraph.more} />
</Page>

<style>
	.article :global(h2) {
		margin-top: 1.5em;
	}

	.article :global(p),
	.article :global(ul),
	.article :global(ol) {
		margin-bottom: 0.75em;
	}

	.article :global(ul),
	.article :global(ol) {
		padding-left: 1.5em;
	}

	.article :global(li) {
		margin-bottom: 0.25em;
	}
</style>
