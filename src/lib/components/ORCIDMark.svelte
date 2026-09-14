<script lang="ts">
	let {
		/** Decorative where a visible label already says "ORCID", announced where it is the
		 * only thing carrying that meaning. Callers that wrap this in their own labelled
		 * element should pass `decorative`, so a screen reader is not told "ORCID iD ORCID
		 * keywords". */
		decorative = false
	}: { decorative?: boolean } = $props();
</script>

<!--
	The ORCID iD mark, on its own. Split out of ORCIDiD.svelte because the keyword groups
	need the glyph WITHOUT a link: they sit in table rows that already carry a ScholarLink,
	and a second link per row pointing somewhere else again would be noise.

	Inline SVG rather than an <img> so it scales with the text it sits in, per ORCID's
	display guidelines. The green is ORCID's own (#A6CE39) and is not themed: it is a brand
	mark, not a themed element.
-->
<svg
	class="mark"
	viewBox="0 0 256 256"
	role={decorative ? 'presentation' : 'img'}
	aria-hidden={decorative ? 'true' : undefined}
	aria-label={decorative ? undefined : 'ORCID iD'}
	xmlns="http://www.w3.org/2000/svg"
>
	<circle cx="128" cy="128" r="128" fill="#A6CE39" />
	<g fill="#FFF">
		<path d="M86.3 186.2H70.9V79.1h15.4v107.1z" />
		<path
			d="M108.9 79.1h41.6c39.6 0 57 28.3 57 53.6 0 27.5-21.5 53.6-56.8 53.6h-41.8V79.1zm15.4 93.3h24.5c34.9 0 42.9-26.5 42.9-39.7 0-21.5-13.7-39.7-43.7-39.7h-23.7v79.4z"
		/>
		<path
			d="M88.7 56.8c0 5.5-4.5 10.1-10.1 10.1s-10.1-4.6-10.1-10.1c0-5.6 4.5-10.1 10.1-10.1s10.1 4.6 10.1 10.1z"
		/>
	</g>
</svg>

<style>
	.mark {
		/* Scaled to the text it sits in, per ORCID's guidelines. */
		width: 1em;
		height: 1em;
		vertical-align: text-bottom;
		flex-shrink: 0;
	}
</style>
