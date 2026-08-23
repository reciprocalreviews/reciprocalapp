<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import { IdeaLabel, ScholarLabel } from '$lib/components/Labels.js';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import Text from '$lib/locales/Text.svelte';
	import { DISCUSSIONS_URL, ISSUES_URL, NEWSLETTER_URL, SUPPORT_EMAIL } from '$lib/community';

	let { data } = $props();
	let { stewards } = $derived(data);
</script>

<Page icon={ScholarLabel} title={(l) => l.page.contact.title} breadcrumbs={[]}>
	<Subheader icon="✉️" text={(l) => l.page.contact.header.write} />

	<Paragraph text={(l) => l.page.contact.paragraph.write} inputs={{ email: SUPPORT_EMAIL }} />
	<Paragraph text={(l) => l.page.contact.paragraph.expectations} />

	<Subheader icon={ScholarLabel} text={(l) => l.page.contact.header.stewards} />

	<Paragraph text={(l) => l.page.contact.paragraph.stewards} />

	<!-- Naming the people is the point of this page: a message to the steward inbox
	     reaches everyone listed here, and each of them replies under their own name. -->
	{#if stewards}
		<ul>
			{#each stewards as steward, index}
				<li>
					<Link to="/scholar/{steward.id}" testid={'steward-' + index}
						>{steward.name ?? 'anonymous'}</Link
					>
				</li>
			{/each}
		</ul>
	{:else}
		<Feedback text={(l) => l.page.contact.feedback.stewardsNotLoaded} />
	{/if}

	<Subheader icon={IdeaLabel} text={(l) => l.page.contact.header.elsewhere} />

	<Paragraph text={(l) => l.page.contact.paragraph.elsewhere} />

	<ul>
		<li><Link to="/help"><Text path={(l) => l.page.contact.link.help} /></Link></li>
		<li>
			<Link to={DISCUSSIONS_URL}><Text path={(l) => l.page.contact.link.discussions} /></Link>
		</li>
		<li><Link to={ISSUES_URL}><Text path={(l) => l.page.contact.link.issues} /></Link></li>
		<li><Link to={NEWSLETTER_URL}><Text path={(l) => l.page.contact.link.newsletter} /></Link></li>
	</ul>
</Page>
