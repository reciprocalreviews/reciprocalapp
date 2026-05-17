<script lang="ts">
	import {
		DeleteLabel,
		IdeaLabel,
		ScholarLabel,
		SettingsLabel,
		UnknownLabel,
		VenueLabel
	} from '$lib/components/Labels';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
</script>

<Page icon={UnknownLabel} title={(l) => l.page.terms.title} breadcrumbs={[]}>
	<Paragraph text={(l) => l.page.terms.paragraph.intro} />

	<Subheader icon="📜" text={(l) => l.page.terms.header.terms} />

	<Subheader sub icon={IdeaLabel} text={(l) => l.page.terms.header.what} />
	<Paragraph text={(l) => l.page.terms.paragraph.what} />

	<Subheader sub icon={ScholarLabel} text={(l) => l.page.terms.header.account} />
	<Paragraph text={(l) => l.page.terms.paragraph.account} />

	<Subheader sub icon="📧" text={(l) => l.page.terms.header.email} />
	<Paragraph text={(l) => l.page.terms.paragraph.email} />

	<Subheader sub icon="📂" text={(l) => l.page.terms.header.data} />
	<Paragraph text={(l) => l.page.terms.paragraph.data} />

	<Subheader sub icon={VenueLabel} text={(l) => l.page.terms.header.venues} />
	<Paragraph text={(l) => l.page.terms.paragraph.venues} />

	<Subheader sub icon="🛠" text={(l) => l.page.terms.header.openSource} />
	<Paragraph text={(l) => l.page.terms.paragraph.openSource} />

	<Subheader sub icon={DeleteLabel} text={(l) => l.page.terms.header.delete} />
	<Paragraph text={(l) => l.page.terms.paragraph.delete} />

	<Subheader sub icon="🔄" text={(l) => l.page.terms.header.changes} />
	<Paragraph text={(l) => l.page.terms.paragraph.changes} />

	<Subheader icon={UnknownLabel} text={(l) => l.page.terms.header.privacy} />

	<Paragraph text={(l) => l.page.terms.paragraph.privacyIntro} />

	<Subheader sub icon="📖" text={(l) => l.page.terms.header.definitions} />
	<Paragraph text={(l) => l.page.terms.paragraph.definitions} />

	<Subheader sub icon="⚖️" text={(l) => l.page.terms.header.legalBasis} />
	<Paragraph text={(l) => l.page.terms.paragraph.legalBasis} />

	<Subheader sub icon="📂" text={(l) => l.page.terms.header.collect} />
	<Paragraph text={(l) => l.page.terms.paragraph.collect} />

	<Subheader sub icon="🗄" text={(l) => l.page.terms.header.retention} />
	<Paragraph text={(l) => l.page.terms.paragraph.retention} />

	<Subheader sub icon="🛡" text={(l) => l.page.terms.header.security} />
	<Paragraph text={(l) => l.page.terms.paragraph.security} />

	<Subheader sub icon="📧" text={(l) => l.page.terms.header.privacyEmail} />
	<Paragraph text={(l) => l.page.terms.paragraph.privacyEmail} />

	<Subheader sub icon={SettingsLabel} text={(l) => l.page.terms.header.rights} />
	<Paragraph text={(l) => l.page.terms.paragraph.rights} />

	<Subheader sub icon="🌐" text={(l) => l.page.terms.header.international} />
	<Paragraph text={(l) => l.page.terms.paragraph.international} />

	<Subheader sub icon="📨" text={(l) => l.page.terms.header.contact} />
	<Paragraph text={(l) => l.page.terms.paragraph.contact} />

	<Subheader sub icon="🔄" text={(l) => l.page.terms.header.privacyChanges} />
	<Paragraph text={(l) => l.page.terms.paragraph.privacyChanges} />
</Page>
