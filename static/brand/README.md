# Brand assets

The Reciprocal Reviews mark: two arrows chasing each other around a circle. Reciprocity,
which is the whole idea. Transparent background, one color, no filters — so it drops onto
any surface and survives the sanitizers that avatar pipelines and email clients run.

`logo.svg` is the source. Everything else is derived from it.

| File                   | What it is                      | Where it's used                                                  |
| ---------------------- | ------------------------------- | ---------------------------------------------------------------- |
| `logo.svg`             | Teal `#007284`, with the shadow | The shareable mark: Google Workspace, GitHub org, the newsletter |
| `logo-white.svg`       | The same, in white              | Dark or colored backgrounds — slides, a colored header           |
| `favicon.svg`          | Teal, flat (no shadow)          | The browser tab, via `app.html`                                  |
| `favicon.png`          | 96px raster of `favicon.svg`    | Fallback for browsers without SVG icon support                   |
| `apple-touch-icon.png` | 180px, on an opaque white tile  | iOS home screen — it ignores SVG and composites onto a tile      |
| `og-image.png`         | 1200×630 social card            | Link previews; Slack, LinkedIn, and iMessage all reject SVG      |

The mark also exists as a Svelte component, [`Logo.svelte`](../../src/lib/components/Logo.svelte),
which draws the same paths with `currentColor` so it inherits whatever color it lands in.
**If you change the geometry, change it in both.**

## Regenerating the rasters

```bash
npm run icons
```

Rasterizes `logo.svg` into the three PNGs above using Playwright's Chromium — the only
rasterizer this repository has. Commit the output. This is deliberately **not** part of
`npm run build`: that runs on Vercel, which has no browser installed.

## The shadow

It is an offset copy of the arrow paths at 28% opacity, not an SVG `filter`. Filters need
an `id`, so two copies of the mark on one page collide; and they are among the first things
mail clients and sanitizers strip. Duplicated geometry has neither problem and rasterizes
identically everywhere.

Every rendering of the mark carries it except the favicon, where at 16–32px the offset is
sub-pixel and only blurs the strokes.
