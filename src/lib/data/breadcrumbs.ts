/**
 * One step of the trail shown in the nav, as a URL and the label to show for it.
 *
 * What is left of this reaches scholars, currencies and help articles. The venue and
 * submission trails that used to be built here are gone: the venue bar names the venue on
 * every route inside one and links to its submissions permanently, which was everything
 * those crumbs said (#176).
 *
 * Breadcrumbs travel in load data rather than being handed up from the page through
 * context. They used to be set in an `$effect`, which does not run during SSR, so the
 * server HTML shipped a nav row without them and hydration inserted the chips — enough,
 * on a narrow screen, to wrap the row and shift the whole page down. Coming from a load
 * they are present in the first render, and they change atomically on navigation.
 */
export type Breadcrumb = [url: string, label: string];
