import type { Action } from 'svelte/action';

/**
 * Keep an element's height in a custom property on the document root.
 *
 * Two bands are sticky: the nav in `Nav.svelte`, and the page title block in
 * `Page.svelte` that pins directly below it. Each needs the other's height — the
 * title block for its `top` offset, and `scroll-padding-block-start` in app.html
 * for the band an anchor has to clear. Neither is knowable in CSS, and both
 * change as the page is used: banners appear and are dismissed, the nav row
 * wraps on a narrow screen, a long title runs to a second line.
 *
 * This runs only after hydration, and that is deliberately safe rather than
 * merely tolerable: it writes a sticky offset and a scroll padding, never a
 * layout height, so nothing it does can move content. Until it first reports,
 * and whenever script is off, the `var()` fallbacks in the CSS stand in.
 */
const measure: Action<HTMLElement, string> = (node, property) => {
	let current = property;

	function write() {
		// `getBoundingClientRect` rather than `offsetHeight`: the latter rounds to whole
		// pixels, and the rounding lands in a sticky offset where it shows up as a
		// hairline of content sliding out from under the band.
		document.documentElement.style.setProperty(current, `${node.getBoundingClientRect().height}px`);
	}

	const observer = new ResizeObserver(write);
	observer.observe(node);
	write();

	return {
		update(next: string) {
			if (next === current) return;
			document.documentElement.style.removeProperty(current);
			current = next;
			write();
		},
		destroy() {
			observer.disconnect();
			document.documentElement.style.removeProperty(current);
		}
	};
};

export default measure;
