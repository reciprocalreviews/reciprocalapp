# Architecture

_Last revised: 2026-05-10_

This document describes the implementation of the Reciprocal Reviews platform — what runs where, how requests flow, and the conventions contributors should follow when extending it. For the user-facing design and rationale, see [DESIGN.md](DESIGN.md). The two documents are intended to stay in sync; changes to either should be audited against the other.

## Stack

Production runtime dependencies are deliberately small. Only three libraries ship to the browser:

- `@supabase/ssr` and `@supabase/supabase-js` — Supabase client (auth, Postgres, Realtime)
- `marked` — Markdown rendering for rich text fields

Everything else is build- or test-time tooling. The full set:

| Concern              | Tool                                          |
| -------------------- | --------------------------------------------- |
| Frontend framework   | Svelte 5 (runes) + SvelteKit 2                |
| Language             | TypeScript (strict)                           |
| Hosting              | Vercel via `@sveltejs/adapter-vercel`         |
| Database, auth, realtime | Supabase (Postgres + GoTrue + Realtime)   |
| Edge functions       | Supabase Functions (Deno)                     |
| Outbound email       | Resend, fronted by an Edge Function           |
| Unit tests           | Vitest (`src/**/*.unit.ts`)                   |
| Integration tests    | Playwright, Chromium only (`end2end/`)        |
| Locale validation    | `ts-json-schema-generator` + `ajv`            |
| Build runtime        | Node ≥ 22                                     |
| Code style           | Prettier (tabs, single quotes, 100-char lines)|

## Request flow

A typical authenticated request:

```
Browser
  │  cookies (Supabase session)
  ▼
Vercel runtime
  │  hooks.server.ts → createServerClient → getClaims (validate JWT)
  ▼
SvelteKit route (+page.ts / +page.svelte / +server.ts)
  │  getDB() → SupabaseCRUD methods
  ▼
Supabase Postgres (RLS-enforced)
  │
  ├──► Postgres Changes ──► RealtimeChannel ──► invalidateAll()
  │                                              (on subscribed clients)
  │
  └──► (writes to `emails` table) ──► resend / remind Edge Functions ──► Resend API
```

Reads are gated by Postgres row-level security, so the database is the last line of defense regardless of what the client requests. Writes that should produce email enqueue rows in the `emails` table; an Edge Function consumes them and posts to Resend in production (or logs to the console in local dev).

## Source tree

```
src/
  app.html, app.d.ts        SvelteKit shell and app-wide types
  hooks.server.ts           Per-request Supabase server client + auth gating
  routes/[[lang]]/          Pages and endpoints; [[lang]] is an optional locale prefix
  lib/
    auth/                   Authentication abstraction
    components/             Shared design-system components (Button, Card, Form, ...)
    data/                   CRUD interface + Supabase implementation, realtime helper
    locales/                LocaleText type, Text component, generated JSON schema
    validation.ts           Shared input validators
  data/
    database.ts             Generated Supabase types (do not edit)
    types.ts                Hand-rolled domain types
  email/
    templates.ts            Email template registry
static/
  locales/en.json           Localized strings (validated against LocaleText.json)
supabase/
  schemas/                  Authoritative declarative table schemas (one file per table)
  migrations/               Timestamped migration history
  functions/                Edge functions (Deno)
  config.toml               Local Supabase config
end2end/                    Playwright integration tests
scripts/
  updates.js                Generates updates.json from CHANGELOG.md at build time
```

## Authentication

Auth is Supabase email/OTP. The integration is centralized so route code never touches Supabase Auth directly.

- [src/hooks.server.ts](src/hooks.server.ts) creates a per-request Supabase server client from cookies and exposes it on `event.locals.supabase`. It also validates the JWT locally via `getClaims()` before any database query, so unauthenticated traffic never reaches the DB.
- [src/lib/auth/Authentication.ts](src/lib/auth/Authentication.ts) and `src/routes/Auth.svelte` wrap session state for client code. Routes consume auth via `getAuth()`.

ORCID-based login is planned (see DESIGN.md and [#19](https://github.com/reciprocalreviews/reciprocalapp/issues/19)) but not yet implemented.

## Data access

All database I/O goes through an abstract interface, not the Supabase client directly. This keeps route code free of database-specific concerns and makes the backend swappable or mockable.

- The interface is [src/lib/data/CRUD.ts](src/lib/data/CRUD.ts).
- The Supabase implementation is [src/lib/data/SupabaseCRUD.svelte.ts](src/lib/data/SupabaseCRUD.svelte.ts), instantiated in the root layout and exposed via `setDB()` / `getDB()`.
- Every method returns `Result<T> = { data?: T; error?: DBError; notified?: Notification[] }`.
- The `handle()` helper in `src/routes/feedback.svelte.ts` wraps calls and posts errors to the global feedback bus, so route code is typically `await handle(db().someMethod(...))`.

New domain operations should be added as methods on the `CRUD` interface and implemented on `SupabaseCRUD`, never as ad-hoc Supabase calls in a route.

## Realtime

Pages stay live by subscribing to Postgres change feeds. The wrapper is [src/lib/data/SupabaseRealtime.ts](src/lib/data/SupabaseRealtime.ts):

```ts
getRealtimeChannel(name, supabase, [{ table, filter }, ...], () => invalidateAll());
```

Each subscription declares the tables and row filters it cares about; the callback usually calls `invalidateAll()` to retrigger SvelteKit's load functions. Routes that depend on shared mutable state should add a channel rather than polling.

A consequence to be aware of: `handle()` also calls `invalidateAll()` after every successful write, and realtime callbacks land asynchronously after a write commits. Any component that holds in-progress user input (a partially-typed field, an open form) must keep a local working copy of that input and only sync from the load-function prop when it isn't actively editing — otherwise the next refetch will overwrite the user's input. [src/lib/components/EditableText.svelte](src/lib/components/EditableText.svelte) is the canonical example of this pattern.

## Email pipeline

Server code never calls Resend directly. The producer / consumer split is:

1. **Producer.** Application code (CRUD methods, edge functions) inserts a row into the `emails` table via `emailScholars(scholars, templateKey, args)`.
2. **Consumer — `resend` function.** [supabase/functions/resend/](supabase/functions/resend/) reads the row, looks up the template in [src/email/templates.ts](src/email/templates.ts), substitutes `$1`/`$2`/... placeholders, and posts to the Resend API. In local dev (when `PUBLIC_SUPABASE_URL` points at 127.0.0.1) it logs to the console instead.
3. **Reminder cron — `remind` function.** [supabase/functions/remind/](supabase/functions/remind/) is invoked daily at 22:00 UTC by a `pg_cron` job (`remind-daily`) defined in `supabase/migrations/`. It emails scholars with stale availability (fixed 90-day staleness, 30-day dedupe) and emails admins + minters about unapproved proposed transactions, gated per venue by `venues.transaction_reminder_frequency_days` and stamped to `venues.transaction_reminder_time`. It is the only producer that runs outside the SvelteKit process.

To add a new email: add a key to the `Emails` map in `templates.ts`, then call `emailScholars(...)` from the appropriate CRUD method.

## Database management

The schema is described in two places, both kept in sync:

- [supabase/schemas/](supabase/schemas/) — declarative schema files, one per table. **Authoritative.** DESIGN.md links here. RLS policies live in the same file as the table definition.
- [supabase/migrations/](supabase/migrations/) — timestamped migration history. Required for every schema change.

Workflow for a schema change:

1. Write a migration in `supabase/migrations/`.
2. Update the matching declarative file in `supabase/schemas/`.
3. Run `npm run reset` locally to rebuild the DB and regenerate `src/data/database.ts`.

`src/data/database.ts` is generated by `npm run types` (`supabase gen types typescript --local`). Never edit it by hand.

RLS is enabled on every table. Tests for RLS policies are tracked at [#79](https://github.com/reciprocalreviews/reciprocalapp/issues/79).

### Submission completion

Submission completion is a guarded action implemented by the `mark_submission_done(submission_id, payment_template, mint_template)` RPC ([supabase/migrations/20260517000000_mark_submission_done.sql](supabase/migrations/20260517000000_mark_submission_done.sql)). It authorizes only priority-0 editors of the submission, validates that every approved non-editor assignment is already completed, and — in one atomic action — compensates every uncompleted priority-0 assignment, flips `submissions.status` to `done`, and stamps `submissions.completed_at`. If the venue cannot cover the total editor payout, it records a single proposed mint sized to the shortfall and returns without changing status; if there are pending non-editor assignments, it returns the blocker list without changing anything.

To enforce this gate, UPDATE privileges on `submissions.status` and `submissions.completed_at` are revoked from the `authenticated` role at the column level. The RPC is `SECURITY DEFINER`, so it is the only path that can write these columns. This is the same RLS-style column-permission pattern used elsewhere in the schema (rather than CHECK constraints or triggers, which can't atomically coordinate writes across tables). The result: **done is terminal** — once set there is no API path to revert it, by design.

Per-editor compensation amounts come from `compensation(role, submission_type)`; multi-editor submissions are supported and all priority-0 editor assignments are paid in the same transaction. The RPC returns a structured JSONB result (`completed | blocked | insufficient`) that the application layer narrows with a runtime type guard before dispatching `WorkCompensated` emails (per-recipient, surfaced as notification banners via the `handle()` feedback channel).

## Locales

Localization is type-driven so the schema cannot drift from the strings:

1. [src/lib/locales/Locale.ts](src/lib/locales/Locale.ts) defines a single `LocaleText` interface — the source of truth for every user-visible string.
2. `npm run locale-schema` runs `ts-json-schema-generator` to emit [src/lib/locales/LocaleText.json](src/lib/locales/LocaleText.json).
3. `npm run locale-validate` runs `ajv` against the per-language JSON files.
4. `npm run locale` does both. Run after any change to `Locale.ts`.

The English locale file lives at [static/locales/en.json](static/locales/en.json). It is loaded server-side in the root layout and exposed via `setLocaleContext()`. Components consume strings through [src/lib/locales/Text.svelte](src/lib/locales/Text.svelte) and locale-typed prop functions:

```svelte
<Text path={(l) => l.page.login.buttons.login} />
<TextField label={(l) => l.page.login.form.email.label} />
```

## Global context

The root layout [src/routes/+layout.svelte](src/routes/+layout.svelte) sets up four context channels consumed throughout the app:

- `setDB()` / `getDB()` — database instance
- `setLocaleContext()` / `getLocaleContext()` — current locale strings
- `setFeedback()` / `getFeedback()` — global error/success notification stack
- `setAuth()` / `getAuth()` — authenticated session and scholar

Plus breadcrumbs and page-header state for the chrome.

## State conventions

- Svelte 5 runes (`$state`, `$derived`, `$effect`) are used throughout.
- Class-based stores (e.g. `SupabaseCRUD`) hold reactive state in `$state` fields. The `.svelte.ts` extension marks a module as rune-aware.
- Prefer `$derived` over `$effect` for computed values; reach for `$effect` only when a true side effect is required.

## Routing

- All routes live under `src/routes/[[lang]]/`. `[[lang]]` is an optional locale prefix that defaults to `en`.
- Dynamic segments use the project's domain identifiers: `[id]` (scholars, currencies), `[venueid]`, `[submissionid]`, `[proposalid]`.
- Route directories may contain `+page.svelte`, `+page.ts`, `+layout.svelte`, `+layout.ts`, plus arbitrary co-located helper Svelte files (e.g. `Roles.svelte`, `NewSubmission.svelte`) when a page is too big for one file.

## UI components

[src/lib/components/](src/lib/components/) is the shared design system: `Button`, `Card`, `Cards`, `Form`, `TextField`, `Slider`, `Tag`, `Tags`, `Page`, `Nav`, `Footer`, `Feedback`, `Loading`, `Dialog`, and so on. New UI should compose these rather than introducing one-off styling. Components accept locale-path functions where they take user-visible text.

## Build and release

- `npm run build` runs [scripts/maybe-updates.js](scripts/maybe-updates.js) first, which invokes `npm run updates` only when `$CI` is set. CI builds regenerate `src/routes/[[lang]]/updates/updates.json` from [CHANGELOG.md](CHANGELOG.md) via [scripts/updates.js](scripts/updates.js); local builds reuse whatever was last committed, so the file doesn't churn on every dev rebuild. Run `npm run updates` manually if you want to regenerate it locally.
- `npm run deploy` merges `dev` → `main` and pushes both branches. The push triggers CI; CI does the actual deploy.
- `package.json#version` is bumped manually as part of changelog updates.

### Deployment pipeline

Vercel's automatic git-deploys are **disabled** for `dev` and `main` (see [vercel.json](vercel.json)`#git.deploymentEnabled`). Deploys are driven by GitHub Actions instead, so a broken push never reaches hosting.

Each branch push triggers a workflow that runs jobs in this order:

```
[unit-tests, playwright, locale-validation]   ── parallel
              │
              ▼ all pass
           migrate         ── supabase db push
              │
              ▼ pass
           vercel          ── vercel pull → build → deploy
```

If any test fails, neither the Supabase migration nor the Vercel deploy runs. Migrations are applied before the Vercel deploy so schema changes are in place before the code that depends on them goes live.

- `dev` → [.github/workflows/staging.yml](.github/workflows/staging.yml) deploys to a Vercel **preview** environment against the staging Supabase project.
- `main` → [.github/workflows/production.yml](.github/workflows/production.yml) deploys to Vercel **production** against the production Supabase project.

Required GitHub secrets: `SUPABASE_ACCESS_TOKEN`, `STAGING_DB_PASSWORD`, `STAGING_PROJECT_ID`, `PRODUCTION_DB_PASSWORD`, `PRODUCTION_PROJECT_ID`, `TEST_ENV`, `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`. Per-environment runtime config (Supabase URL, anon key, Resend key, etc.) lives in Vercel's environment variable settings and is pulled at build time by `vercel pull`.

## Testing

- **Unit.** Vitest. Files matching `src/**/*.unit.ts`. Run with `npm run test:unit`.
- **Integration.** Playwright, Chromium only. Files in `end2end/`. Run with `npm run test:end`. The suite expects a local Supabase running with seed data; see `npm start` and `npm run reset`.
- **Combined.** `npm test` runs end2end then unit.

## Local development

```sh
npm install
npm run start       # supabase start (skips storage, imgproxy, logflare, supavisor, vector) + serves edge functions
npm run dev         # Vite dev server
npm run reset       # supabase db reset + regenerate src/data/database.ts
npm run check:now   # one-shot svelte-check
npm run locale      # validate locales
npm run stop        # supabase stop
```

`.env` (gitignored) supplies `RESEND_API_KEY` and any other secrets. Without it, the `resend` function logs to the console rather than sending mail, which is the intended local-dev behavior.
