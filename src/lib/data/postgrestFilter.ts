/**
 * Quoting values into a PostgREST filter that is built as a string.
 *
 * Most reads use the query builder's own `eq` and `in`, which encode their arguments.
 * A couple do not, because matching one typed string against two columns in a single
 * round trip means composing an `or()` filter — and `or()` takes a string, so its
 * values are concatenated in by hand. That is the only place these helpers belong.
 *
 * The escaping is not hypothetical. `validEmail` permits `"` and `\` in a local part,
 * so `a"b@c.co` is an address the invite field accepts; concatenated into a filter with
 * only quotes around it, it closes the quoted value early and the remainder is read as
 * filter syntax.
 *
 * Deliberately stricter than supabase-js's own `in()`, which quotes only when a value
 * contains `,`, `(`, or `)` and escapes nothing at all — so it mangles the same inputs,
 * just by a different route. Do not reach for it as the reference implementation.
 */

/** Quote one value for a PostgREST filter.
 *
 * Always quoted, with `\` and `"` backslash-escaped, which is what PostgREST's grammar
 * allows inside a double-quoted value. Backslashes first, or the escapes escape each
 * other. */
export function quoteFilterValue(value: string): string {
	return `"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"`;
}

/** A `column.in.("a","b")` clause for use inside an `or()` filter.
 *
 * An empty list produces `column.in.()`, which PostgREST rejects as a syntax error
 * rather than answering with no rows — so callers guard the empty case before they get
 * here, instead of relying on this to do something sensible with it. */
export function inFilter(column: string, values: string[]): string {
	return `${column}.in.(${values.map(quoteFilterValue).join(',')})`;
}

/** A `column.eq."value"` clause for use inside an `or()` filter.
 *
 * Quoted for the same reason as the rest: `validEmail` permits `(` and `)`, so an
 * unquoted `a(b@c.co` closes the surrounding `or()` early and the request comes back a
 * 400 instead of a clean "nobody by that name". */
export function eqFilter(column: string, value: string): string {
	return `${column}.eq.${quoteFilterValue(value)}`;
}
