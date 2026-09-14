<script lang="ts">
	import { orcidURL } from '$lib/data/ORCID';
	import Link from './Link.svelte';
	import ORCIDMark from './ORCIDMark.svelte';

	let {
		id,
		/** Icon only, for a place where the iD itself would only repeat what is beside it.
		 * The link and its accessible name stay either way. */
		compact = false,
		testid = undefined
	}: { id: string; compact?: boolean; testid?: string } = $props();
</script>

<!--
	ORCID's display guidelines ask for the full https URI preceded by the green iD mark, both
	hyperlinked to that URI, with the mark scaled to the height of the text. RR used to render
	a bare `orcid.org/{id}` with no scheme and no mark.

	The testid goes on the LINK rather than this wrapper, because callers assert its href.
-->
<span class="orcid">
	<Link to={orcidURL(id)} {testid}>
		<ORCIDMark decorative={!compact} />{#if !compact}<span class="id">orcid.org/{id}</span>{/if}
	</Link>
</span>

<style>
	.orcid {
		display: inline-flex;
		align-items: center;
	}

	.id {
		/* The buffer ORCID's guidelines ask for beside the mark, expressed as a margin on
		   the text rather than on the mark: the compact form has no text after it, and a
		   trailing margin there would pad the link for nothing. */
		margin-inline-start: 0.5em;
		word-break: break-all;
	}
</style>
