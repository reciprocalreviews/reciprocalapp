<script lang="ts">
	import type LocaleText from '$lib/locales/Locale';
	import Logo from '$lib/components/Logo.svelte';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import Text from '$lib/locales/Text.svelte';
	const REPO = 'https://github.com/reciprocalreviews/reciprocalapp/tree/main/static/brand';

	/** Read off the `:root` block in src/app.html. Listed rather than read from
	 * `getComputedStyle` so the swatch and its label cannot disagree: a hex here that
	 * has drifted from the stylesheet is visible the moment the two sit side by side. */
	const COLORS = [
		{ name: 'Salient', hex: '#007284', role: 'Links, headers, the token chip' },
		{ name: 'Salient faded', hex: '#e1eff2', role: 'Emphasis blocks and chips' },
		{ name: 'Focus', hex: '#db501e', role: 'Keyboard focus, and nothing else' },
		{ name: 'Error', hex: '#840054', role: 'Errors and debits' },
		{ name: 'Error faded', hex: '#ffdceb', role: 'Error backgrounds' },
		{ name: 'Border', hex: '#bbbbbb', role: 'Rules and outlines' },
		{ name: 'Alternating', hex: '#f3f3f3', role: 'Table row banding' },
		{ name: 'Inactive', hex: '#888888', role: 'Disabled and muted text' }
	];

	const FILES = [
		{ file: 'logo.svg', label: (l: LocaleText) => l.page.brand.file.logo },
		{ file: 'logo-white.svg', label: (l: LocaleText) => l.page.brand.file.logoWhite },
		{ file: 'favicon.svg', label: (l: LocaleText) => l.page.brand.file.favicon },
		{ file: 'apple-touch-icon.png', label: (l: LocaleText) => l.page.brand.file.touch },
		{ file: 'og-image.png', label: (l: LocaleText) => l.page.brand.file.social }
	];
</script>

<Page title={(l) => l.page.brand.title} breadcrumbs={[]}>
	{#snippet icon()}<Logo />{/snippet}

	<p class="lead"><Text path={(l) => l.page.brand.lead} /></p>

	<Subheader icon="🔄" text={(l) => l.page.brand.header.mark} />
	<Paragraph text={(l) => l.page.brand.paragraph.mark} />

	<!-- The mark at the sizes it actually gets used at, on both grounds it lands on,
	     so the page shows the thing rather than describing it. -->
	<div class="specimens">
		<div class="specimen light"><Logo size="6rem" /></div>
		<div class="specimen dark"><Logo size="6rem" /></div>
		<div class="specimen light sizes">
			<Logo size="3rem" /><Logo size="2rem" /><Logo size="1.5rem" /><Logo size="1rem" />
		</div>
	</div>

	<ul class="files">
		{#each FILES as { file, label }}
			<li>
				<a href="/brand/{file}" download>
					<Text path={label} />
					<code>{file}</code>
				</a>
			</li>
		{/each}
	</ul>

	<Paragraph text={(l) => l.page.brand.paragraph.usage} inputs={{ repo: REPO }} />

	<Subheader icon="🎨" text={(l) => l.page.brand.header.color} />
	<Paragraph text={(l) => l.page.brand.paragraph.color} />

	<ul class="colors">
		{#each COLORS as { name, hex, role }}
			<li>
				<span class="swatch" style="background: {hex}"></span>
				<span class="name">{name}</span>
				<code>{hex}</code>
				<span class="role">{role}</span>
			</li>
		{/each}
	</ul>

	<Subheader icon="🔤" text={(l) => l.page.brand.header.type} />
	<Paragraph text={(l) => l.page.brand.paragraph.type} />

	<div class="type">
		<div>
			<span class="caption"><Text path={(l) => l.page.brand.label.heading} /> · Quicksand</span>
			<p class="quicksand">Make peer review count.</p>
		</div>
		<div>
			<span class="caption"><Text path={(l) => l.page.brand.label.body} /> · Josefin Sans</span>
			<p class="josefin">Authors earn tokens by reviewing, and spend them to submit.</p>
		</div>
	</div>
</Page>

<style>
	.lead {
		font-size: var(--subsubheader-font-size);
		font-style: italic;
		color: var(--inactive-color);
		margin: 0;
	}

	.specimens {
		display: flex;
		flex-wrap: wrap;
		gap: var(--spacing);
	}

	.specimen {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: var(--spacing);
		padding: var(--spacing);
		border-radius: var(--roundedness);
		flex: 1 1 10rem;
	}

	.specimen.light {
		background: var(--alternating-color);
		color: var(--salient-color);
	}

	.specimen.dark {
		background: var(--salient-color);
		color: var(--background-color);
	}

	.sizes {
		align-items: baseline;
	}

	.files,
	.colors {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--spacing-half);
	}

	.files {
		flex-direction: row;
		flex-wrap: wrap;
		gap: var(--spacing);
	}

	.files a {
		font-size: var(--small-font-size);
	}

	.colors li {
		display: flex;
		align-items: center;
		gap: var(--spacing-half);
		font-size: var(--small-font-size);
		margin: 0;
	}

	.swatch {
		width: 1.75rem;
		height: 1.75rem;
		border-radius: var(--roundedness);
		border: var(--border-width) solid var(--border-color);
		flex: none;
	}

	.name {
		font-weight: 500;
		min-width: 8rem;
	}

	.role {
		color: var(--inactive-color);
		font-style: italic;
	}

	.type {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
	}

	.caption {
		font-size: var(--extra-small-font-size);
		color: var(--inactive-color);
		font-style: italic;
	}

	.quicksand {
		font-family: 'Quicksand', sans-serif;
		font-weight: 500;
		font-size: var(--subheader-font-size);
	}

	.josefin {
		font-family: 'Josefin Sans', sans-serif;
		font-weight: 300;
		font-size: var(--subsubheader-font-size);
	}
</style>
