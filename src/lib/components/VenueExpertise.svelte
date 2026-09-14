<script lang="ts">
	import type { Snippet } from 'svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import Logo from './Logo.svelte';

	let { children, testid = undefined }: { children: Snippet; testid?: string } = $props();

	const locale = getLocaleContext();
</script>

<!--
	What a volunteer told THIS venue about reviewing, marked with the platform's own logo.

	The pair with ORCIDKeywords is the whole point: each side of an expertise cell is labelled
	by whose claim it is, so either can stand alone without being mistaken for the other. That
	replaced an em-dash standing in for "they told us nothing", which said nothing legible to
	anyone who had not been told what it meant.

	`shadow={false}` for the same reason the favicon turns it off: at roughly one em the mark's
	offset ghost is sub-pixel and only softens the strokes.
-->
<span class="venue-expertise" data-testid={testid}>
	<Logo size="1em" shadow={false} />
	<span class="label">{locale().view.expertise.venue}</span>
	{@render children()}
</span>

<style>
	.venue-expertise {
		/* Block-level, so the two sources stack rather than running together on one line.
		   Each row carries its own mark, so a row that is absent takes no space and leaves
		   no gap — which is the property the old dotted rule could not have. */
		display: flex;
		width: fit-content;
		max-width: 100%;
		flex-wrap: wrap;
		/* Centred, not baseline-aligned: an SVG has no baseline, so `baseline` puts its
		   bottom edge on the text's and lifts the mark above the optical centre of the
		   chips beside it. */
		align-items: center;
		gap: var(--spacing-half);
		color: var(--salient-color, inherit);
	}

	/* Visually hidden, still announced. */
	.label {
		position: absolute;
		width: 1px;
		height: 1px;
		margin: -1px;
		padding: 0;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
		border: 0;
	}
</style>
