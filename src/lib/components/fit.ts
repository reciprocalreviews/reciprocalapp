/**
 * How many of a row's collapsible items fit in it.
 *
 * Separated from `Overflow.svelte` because this is the part with an off-by-one in it: the
 * control that reveals the collapsed items only exists WHEN something is collapsed, so
 * charging for its width unconditionally gives up one item too many, and never charging
 * for it keeps one too many. Splitting the question in two — "does everything fit with no
 * control at all?" first, "how many fit beside the control?" second — is the whole of the
 * fix, and it is the kind of rule this codebase keeps in a module where a test can reach
 * it rather than in a component where nothing can.
 */

export type Fit = {
	/** The row's content width: its border box less its inline padding. */
	available: number;
	/** What the row needs for everything that is NOT one of these items and not the
	 * control — the mark, the trail, the balance, the venue's name. */
	base: number;
	/** Each item's width, in the order they appear. The row collapses from the END, so the
	 * last of these is the first to go. */
	widths: number[];
	/** The control's width. Charged once, and only when something is collapsed. */
	toggle: number;
	/** The flex row's column gap. Every item is charged one. */
	gap: number;
};

/**
 * Widths come back fractional, and a row short by a hundredth of a pixel is not a row that
 * overflows. Half a pixel is below anything a reader can see and well above the error in a
 * `getBoundingClientRect`.
 */
const TOLERANCE = 0.5;

export function fits({ available, base, widths, toggle, gap }: Fit): number {
	// First question: with no control at all, is there room for everything? It has to be
	// asked separately, or the control's own width is what pushes the last item out — and
	// then the control is there only to reveal an item that left because it arrived.
	const whole = widths.reduce((total, width) => total + width + gap, base);
	if (whole <= available + TOLERANCE) return widths.length;

	// Second question: the control is needed now, so how many fit beside it? This loop
	// cannot reach the end of `widths` — if it could, `whole` would have fit.
	let needed = base + toggle + gap;
	let count = 0;
	while (count < widths.length && needed + widths[count] + gap <= available + TOLERANCE) {
		needed += widths[count] + gap;
		count += 1;
	}
	return count;
}
