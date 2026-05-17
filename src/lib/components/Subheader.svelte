<script lang="ts">
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import monoEmoji from './monoEmoji';

	interface Props {
		icon: string;
		text: string | ((locale: LocaleText) => string | string[]);
		id?: string;
	}

	let { icon, id, text }: Props = $props();

	const locale = getLocaleContext();

	const LinkLabel = monoEmoji('🔗');

	const headerId = $derived.by(() => {
		if (id) return id;
		const resolved = typeof text === 'function' ? text(locale()) : text;
		const str = Array.isArray(resolved) ? resolved.join(' ') : resolved;
		return str
			.toLowerCase()
			.replace(/[^a-z0-9]+/g, '-')
			.replace(/^-+|-+$/g, '');
	});

	function copyLink(event: MouseEvent) {
		event.preventDefault();
		history.pushState(null, '', `#${headerId}`);
		window.dispatchEvent(new HashChangeEvent('hashchange'));
	}
</script>

<h2 id={headerId}>
	<span class="anchor-slot">
		<a
			class="anchor"
			href="#{headerId}"
			title={locale().widget.subheader.link}
			onclick={copyLink}>{LinkLabel}</a
		>
	</span>
	{#if typeof text === 'string'}{text}{:else}<Text path={text} />{/if}
	<span class="icon">{icon}</span>
</h2>

<style>
	h2 {
		display: flex;
		gap: 0.25rem;
		align-items: baseline;
	}

	/* Reserves a baseline-aligned slot for the anchor but contributes no
	   width, so the title sits where it would without the anchor. The
	   anchor is translated into the left gutter visually while staying on
	   the heading's baseline through normal inline flow. */
	.anchor-slot {
		width: 0;
		margin-right: -0.25rem;
		font-size: var(--paragraph-font-size);
	}

	.anchor {
		display: inline-block;
		transform: translateX(calc(-100% - 0.5rem));
		white-space: nowrap;
		text-decoration: none;
	}

	.icon,
	.anchor {
		font-family: 'Noto Emoji', 'Josefin Sans', sans-serif;
		color: var(--border-color);
		font-size: var(--paragraph-font-size);
	}
</style>
