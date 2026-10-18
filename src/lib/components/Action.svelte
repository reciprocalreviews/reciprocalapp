<script lang="ts">
	import type LocaleText from '#lib/locales/Locale.js';
	import Text from '#lib/locales/Text.svelte';
	import Link from './Link.svelte';
	import Tag from './Tag.svelte';

	/**
	 * One thing the viewer can go and do from this page, in a page's actions row.
	 *
	 * Tools used to be reached through prose — "Welcome admin! Check the settings…",
	 * "Importing pre-launch submissions? Import…" — which read as notices and said the same
	 * thing on every visit. An action is a link that looks like one, says which role it is
	 * for, and carries a count when there is work waiting behind it.
	 */
	let {
		to,
		label,
		group,
		count,
		testid
	}: {
		to: string;
		label: (l: LocaleText) => string;
		/** Who the tool is for. Absent for actions anyone on the page can take. */
		group?: 'admin' | 'editor' | 'minter' | 'steward';
		/** Work waiting behind the action — unmatched names, say. Hidden when zero. */
		count?: number;
		testid?: string;
	} = $props();
</script>

<span class="action" class:tool={group !== undefined} data-testid={testid}
	><Link {to} size="small"><Text path={label} /></Link>{#if count !== undefined && count > 0}<span
			class="count">{count}</span
		>{/if}{#if group}<Tag><Text path={(l) => l.shorthand[group]} /></Tag>{/if}</span
>

<style>
	.action {
		display: inline-flex;
		align-items: baseline;
		gap: var(--spacing-half);
		padding: calc(var(--spacing) / 4) var(--spacing-half);
		border: var(--border-width) solid var(--salient-color);
		border-radius: var(--roundedness);
		white-space: nowrap;
	}

	/* Role tools sit back a step from what anyone can do, so the row reads participant
	   actions first even where a tool comes earlier in the source. */
	.tool {
		border-color: var(--border-color);
	}

	.count {
		background: var(--focus-color);
		color: var(--background-color);
		border-radius: 1em;
		padding: 0 0.5em;
		font-size: var(--extra-small-font-size);
		font-weight: bold;
	}
</style>
