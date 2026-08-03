# Architecture

_Last revised: 2026-05-10_

This document describes the implementation of the Reciprocal Reviews platform — what runs where, how requests flow, and the conventions contributors should follow when extending it. For the user-facing design and rationale, see [DESIGN.md](DESIGN.md). The two documents are intended to stay in sync; changes to either should be audited against the other.

## Stack

Production runtime dependencies are deliberately small. Only three libraries ship to the browser:

- `@supabase/ssr` and `@supabase/supabase-js` — Supabase client (auth, Postgres, Realtime)
- `marked` — Markdown rendering for rich text fields

Everything else is build- or test-time tooling. The full set:

| Concern                  | Tool                                           |
| ------------------------ | ---------------------------------------------- |
| Frontend framework       | Svelte 5 (runes) + SvelteKit 2                 |
| Language                 | TypeScript (strict)                            |
| Hosting                  | Vercel via `@sveltejs/adapter-vercel`          |
| Database, auth, realtime | Supabase (Postgres + GoTrue + Realtime)        |
| Edge functions           | Supabase Functions (Deno)                      |
| Outbound email           | Resend, fronted by an Edge Function            |
| Unit tests               | Vitest (`src/**/*.unit.ts`)                    |
| Integration tests        | Playwright, Chromium only (`end2end/`)         |
| Locale validation        | `ts-json-schema-generator` + `ajv`             |
| Build runtime            | Node ≥ 22                                      |
| Code style               | Prettier (tabs, single quotes, 100-char lines) |

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

Auth is **ORCID**, via Supabase's custom OIDC provider ([#19](https://github.com/reciprocalreviews/reciprocalapp/issues/19)) — the exclusive, mandatory sign-in. The integration is centralized so route code never touches Supabase Auth directly.

- [src/routes/[[lang]]/login/+page.svelte](src/routes/[[lang]]/login/+page.svelte) offers a single "Sign in with ORCID" button. `SupabaseAuth.signInWithORCID()` ([src/routes/Auth.svelte.ts](src/routes/Auth.svelte.ts)) calls `signInWithOAuth({ provider: 'custom:orcid', scopes: 'openid' })`; ORCID returns to [src/routes/auth/callback/+server.ts](src/routes/auth/callback/+server.ts), which does the PKCE `exchangeCodeForSession` and lands the scholar at `/scholar/[id]`. A failed exchange returns to `/login?error=orcid`, which the login page surfaces rather than failing silently.
- **The provider identifier must carry the `custom:` prefix.** Supabase requires it for custom OAuth/OIDC providers; a bare `'orcid'` is rejected at `/auth/v1/authorize`. Do not cast the value — `Provider` already admits `` `custom:${string}` ``, so a wrong slug is caught by `npm run check:now` instead of failing only in a hosted environment, which is how the wrong value survived review once already.
- The provider is configured in the hosted Supabase Dashboard (Authentication → Providers → New Provider → **Auto-discovery (OIDC)**), with the bare issuer URL `https://orcid.org` (staging: `https://sandbox.orcid.org`), scope `openid`, and **`email_optional = true`** — ORCID releases no email on any membership tier, and without that flag GoTrue refuses to create the user. Custom OIDC cannot be expressed in `config.toml`, so local dev and CI use a password grant instead.
- On first sign-in the `handle_new_scholar` trigger creates the scholar row from the OIDC metadata (`orcid`/`name`); it does **not** set an email (ORCID does not release one).
- [src/hooks.server.ts](src/hooks.server.ts) creates a per-request Supabase server client from cookies and exposes it on `event.locals.supabase`. The JWT is validated locally via `getClaims()` in [src/routes/+layout.ts](src/routes/+layout.ts) before scholar data is loaded.
- [src/lib/auth/Authentication.ts](src/lib/auth/Authentication.ts) and `src/routes/Auth.svelte` wrap session state for client code. Routes consume auth via `getAuth()`.
- **Expired-session handling.** When a session dies (token expiry, a revoked refresh token, or a local DB reset), the scholar is sent to `/login` instead of being left on an authenticated page where every write fails with a cryptic RLS/permission error. Two hooks cover it, gated by [`requiresAuth()`](src/lib/auth/requiresAuth.ts) (public routes — landing, login, about, terms, updates, verify — are exempt): the layout load ([+layout.ts](src/routes/+layout.ts)) redirects when an auth cookie is present but `getClaims()` yields no user (a present-but-invalid session — distinct from an anonymous visitor, who has no cookie and is not redirected); and the `onAuthStateChange` listener in [+layout.svelte](src/routes/+layout.svelte) redirects on a live `SIGNED_OUT` event.

**Contact email + verification (app-level, #27).** Because ORCID carries no email, a scholar's contact email is collected separately and its ownership verified in-app — independent of Supabase auth. `scholars.email` holds only a **verified** address (or null). Two things enforce that, and both are needed: it is written solely by the `verify_email` RPC, and the column privilege to write it is revoked (see Column privileges below).

A logged-in scholar with no verified email sees a persistent banner ([Banners.svelte](src/lib/components/Banners.svelte)) and receives no notifications. Requesting or changing an email (`requestEmailVerification` in [SupabaseCRUD](src/lib/data/SupabaseCRUD.svelte.ts)) calls the `request_email_verification` RPC, which does everything inside the database: it stores a pending candidate and a sha256 token hash in `email_verifications` (deny-all RLS, 15-minute expiry, one active request per scholar, one-minute cooldown), builds the link from the `site_url` vault secret, and queues the branded email itself.

**The RPC returns nothing.** The raw token never reaches the client, and the caller supplies neither the message body nor the link's origin. Each of those is load-bearing: returning the token let anyone read it from the network tab and confirm an address they did not control; a caller-supplied body plus a caller-chosen recipient is an open relay; and a caller-supplied origin would put a link to a host of their choosing inside genuinely branded mail. The queued row is written with a **null `scholar` and `sender`** so that no branch of the `emails` SELECT policy matches it — otherwise the requester could read the token straight back out of the row.

The anon-callable `verify_email` RPC ([src/routes/[[lang]]/verify/[token]/+page.server.ts](src/routes/[[lang]]/verify/[token]/+page.server.ts)) validates the token and commits the candidate into `scholars.email`. It deliberately does **not** delete the request: verification is idempotent within the 15-minute window, so an email security scanner or a link prefetch cannot burn the link before the scholar clicks it.

**Column privileges on `scholars`.** The update policy authorizes the row but says nothing about columns, and `grant all` gave `authenticated` a table-wide UPDATE — so a scholar could set `steward = true` on themselves, rewrite `orcid` to claim another researcher's identity, or set `email` directly and skip verification entirely. Because a column-level revoke is a no-op while the table-level privilege stands (as in [20260601000000_rls_corrections.sql](supabase/migrations/20260601000000_rls_corrections.sql)), the table UPDATE is revoked and only `name`, `available`, `status`, `status_time` are re-granted. `email` is written by `verify_email` and `status_reminder_time` by the remind function, both of which bypass these grants. Covered by [scholars_columns_rls.sql](supabase/tests/rls/scholars_columns_rls.sql) — the pre-existing row-level tests all passed while this was open.

## Data access

All database I/O — both the write path and the page-load read path — goes through an abstract interface, not the Supabase client directly. This keeps route code free of database-specific concerns and makes the backend swappable or mockable.

- The interface is [src/lib/data/CRUD.ts](src/lib/data/CRUD.ts).
- The Supabase implementation is [src/lib/data/SupabaseCRUD.svelte.ts](src/lib/data/SupabaseCRUD.svelte.ts). The root [src/routes/+layout.ts](src/routes/+layout.ts) builds a single instance, returns it as the `db` load datum, and the root `+layout.svelte` exposes that same instance via `setDB()` / `getDB()`.
- **Writes** return `Result<T> = { data?: T; error?: DBError; notified?: Notification[] }`. The `handle()` helper in `src/routes/feedback.svelte.ts` wraps calls and posts errors to the global feedback bus, so component code is typically `await handle(db().someMethod(...))`.
- **Reads used by load functions** return `ReadResult<T> = { data: T; error?: DBError }` — `data` is always present (null on a missing row or a failed query) so loads can destructure `data` with the same nullability the raw query builder gave them. Read failures are logged by the implementation, not surfaced. Load functions obtain the instance via `const { db } = await parent()` and call `db.getX(...)`; they never touch the query builder ([#137](https://github.com/reciprocalreviews/reciprocalapp/issues/137)).
- The raw Supabase client is **not** returned as load data. It is reachable only through `db.client`, the single sanctioned escape hatch, used only by auth (`+layout.svelte`, `getClaims()`) and realtime ([src/lib/data/SupabaseRealtime.ts](src/lib/data/SupabaseRealtime.ts)).

New domain operations should be added as methods on the `CRUD` interface and implemented on `SupabaseCRUD`, never as ad-hoc Supabase calls in a route.

### Atomic operations

Operations that perform more than one write — minting or moving tokens, recording a payment alongside the tokens it moves, provisioning a venue — run as `SECURITY DEFINER` Postgres RPCs so each completes in a single transaction; a connectivity loss can no longer leave partial state (tokens moved with no transaction recorded, a submission with orphaned proposed payments, a half-provisioned venue). The CRUD method resolves/validates inputs (reads), calls the RPC for the atomic write, and surfaces the result. Because `SECURITY DEFINER` bypasses RLS, each RPC re-implements its tables' authorization and anti-self-dealing rules in its own body.

The atomic RPCs are `mint_tokens`, `transfer_tokens`, `approve_transaction`, `create_submission`, `create_volunteer` / `accept_role_invite` (volunteer record plus its welcome grant), and `approve_venue_proposal` ([#136](https://github.com/reciprocalreviews/reciprocalapp/issues/136)), alongside the pre-existing `complete_assignment`, `mark_submission_done`, and `bulk_import_submissions`. Each is defined in a migration and mirrored into the relevant `supabase/schemas/` file so it sits next to the table it operates on.

For tokens, the RPCs are not merely the preferred path but the **only** one. `INSERT`, `UPDATE`, and `DELETE` on `public.tokens` are revoked from `authenticated` and `anon`, so a direct PostgREST write fails with `42501`; the remaining policies are explicit denials that document the intent and let the pgTAP suite assert it. This closed a hole in which the owning scholar could `PATCH /rest/v1/tokens` and reassign a token to anyone with **no `transactions` row written at all** — and, because the UPDATE policy's `WITH CHECK` was `true` and so pinned nothing about the resulting row, could also rewrite a token's `currency` and counterfeit value in a currency they were never granted (a balance is `count(*)` of token rows in that currency). Because the RPCs are `SECURITY DEFINER` and owned by `postgres`, the revoke does not touch them.

## Realtime

Pages stay live by subscribing to Postgres change feeds. The wrapper is [src/lib/data/SupabaseRealtime.ts](src/lib/data/SupabaseRealtime.ts):

```ts
getRealtimeChannel(name, supabase, [{ table, filter }, ...], () => invalidateAll());
```

Each subscription declares the tables and row filters it cares about; the callback usually calls `invalidateAll()` to retrigger SvelteKit's load functions. Routes that depend on shared mutable state should add a channel rather than polling.

A consequence to be aware of: `handle()` also calls `invalidateAll()` after every successful write, and realtime callbacks land asynchronously after a write commits. Any component that holds in-progress user input (a partially-typed field, an open form) must keep a local working copy of that input and only sync from the load-function prop when it isn't actively editing — otherwise the next refetch will overwrite the user's input. [src/lib/components/EditableText.svelte](src/lib/components/EditableText.svelte) is the canonical example of this pattern.

## Email pipeline

Email is **application email** — transactional, reminder, and contact-email verification — all sharing one branded visual identity. (Supabase GoTrue no longer sends auth email: sign-in is ORCID and email verification is app-level, so the auth-email path is dormant — see below.) Templates are English only: there is no mechanism yet to solicit a scholar's language preference.

### Application emails

Server code never calls Resend directly. The producer / consumer split is:

1. **Producer.** Application code calls `emailScholars(scholars, templateKey, args)` (in [SupabaseCRUD](src/lib/data/SupabaseCRUD.svelte.ts)), which goes through the `queue_email` RPC. **Direct INSERT into `emails` is revoked** from `authenticated` and `anon`: inserting a row sends branded mail, so an insert policy meant any signed-in user could name any recipient with any body — an open relay from `notifications@reciprocal.reviews`, and self-service ORCID sign-up makes "authenticated" a low bar. `queue_email` resolves recipients server-side from scholar ids (skipping anyone without a verified contact email, which is what enforces "never notify an unverified address") or, for `ProposalCreatedEditors`, from the proposal's own editor list. It accepts **no message body at all**.
2. **Consumer — `resend` function.** [supabase/functions/resend/](supabase/functions/resend/) posts to the Resend API, wrapping the body in the shared branded HTML shell ([supabase/functions/\_shared/emailShell.ts](supabase/functions/_shared/emailShell.ts)) and sending both an HTML and a text/plain alternative. In local dev (when `PUBLIC_SUPABASE_URL` points at 127.0.0.1) it logs to the console instead. **It requires the caller to present one of the project's secret keys** ([\_shared/auth.ts](supabase/functions/_shared/auth.ts)) — see Edge function authorization below. The `remind` function carries the same guard.
3. **Rendering happens at send time, not at the call site.** Rows carry `event` + `args`; the `resend` function renders them from the registry, which now lives at [supabase/functions/\_shared/templates.ts](supabase/functions/_shared/templates.ts) (re-exported from `src/email/templates.ts` for app code) so both runtimes share one source of truth. `subject`/`message` are nullable and null for such rows — `event` + `args` is a complete, re-renderable record. A caller can choose the template and its argument *values* but cannot author prose, and `renderEmail` defangs URL schemes in argument values (`https://x` → `https[:]//x`) so a supplied value cannot become a clickable link inside branded mail. Templates opt specific positions out via `urlArgs` when the link is server-generated — only `VerifyEmail` does, which is why `queue_email` refuses to queue it.
4. **Reminder cron — `remind` function.** [supabase/functions/remind/](supabase/functions/remind/) is invoked daily at 22:00 UTC by a `pg_cron` job (`remind-daily`) defined in `supabase/migrations/`. It emails scholars with stale availability (fixed 90-day staleness, 30-day dedupe) and emails admins + minters about unapproved proposed transactions, gated per venue by `venues.transaction_reminder_frequency_days` and stamped to `venues.transaction_reminder_time`. It builds plain-text bodies, wraps them in the same shared shell, and posts directly to Resend. It is the only producer that runs outside the SvelteKit process.
5. **Server-side fan-out — thank-you notes.** Author thank-you notes to reviewers (#22; the `thanks` table, vetting toggled by `venues.vet_thanks`) need privileged recipient resolution: the author may not see who reviewed their submission. The note bodies are still rendered from the `Emails` registry in `templates.ts` like every other email (`ThanksPendingReview` / `ThanksReceived` / `ThanksDeclined`), but the fan-out goes through the `queue_thanks_emails` RPC (`SECURITY DEFINER`) instead of `emailScholars`. The CRUD layer renders the copy and passes it in; the RPC resolves the audience (the submission's approved assignees / the venue's vetters / the author) and inserts rows into `emails` with `sender = null` so a recipient can't read the author's id off the email row. Its per-audience authorization is also what stops an author from bypassing vetting to message reviewers directly. The `resend` consumer brands and delivers these rows like any other.

To add a new email: add a key to the `Emails` map in `templates.ts`, then send it — from application code via `emailScholars(...)`, or (when recipients must be resolved with elevated privileges, as for thank-you notes) via a `SECURITY DEFINER` fan-out RPC. There is deliberately no path that accepts a free-text address or a caller-authored body; if a new email needs recipients that aren't scholar ids, resolve them inside the RPC from a row the caller already had permission to write.

**Residual, deliberately deferred:** `queue_email` does not yet verify that the caller has a *relationship* to each recipient, so a scholar can send a real template to a scholar they have no business emailing. That is bounded — no arbitrary prose, no external addresses, no attacker-supplied links — and attributable via `emails.sender`. Per-event authorization is a follow-up.

### Edge function authorization

Both functions are called only by the database — `resend` from the `send_on_email_insert` trigger, `remind` from the `remind-daily` cron — and both refuse callers that do not present one of the project's **secret** keys.

The check is deliberately a direct key comparison rather than a JWT claims check. Supabase's newer API keys (`sb_publishable_...` / `sb_secret_...`) are **opaque strings, not JWTs**, so there is no `role` claim to inspect; a claims-based check breaks the moment a project migrates key formats. Comparing the presented key against the keys the runtime injects works for both the legacy `service_role` JWT and the new secret keys, which is what lets the two formats coexist during a migration.

Three consequences worth knowing before touching this code:

- **`verify_jwt` is off** for both functions ([config.toml](supabase/config.toml)). The platform gate only understands JWT-shaped credentials and rejects the new API keys outright. That makes the handler check the *only* gate, so it fails closed: if no secret key is present in the environment, every request is refused. It is also strictly narrower than `verify_jwt` ever was, since `verify_jwt` accepted any valid project JWT — including the public anon key.
- **The key travels on the `apikey` header**, not `Authorization: Bearer`, which is reserved for JWTs and rejects a new-format key as malformed. `send_email()` and the cron job both send it that way; the handler accepts either header so legacy callers keep working.
- **Local development needs `EDGE_SECRET_KEY`** in `.env`. Hosted runtimes inject `SUPABASE_SECRET_KEYS` and `SUPABASE_SERVICE_ROLE_KEY` automatically, but the CLI refuses to pass any `--env-file` entry beginning with `SUPABASE_`, so the local name cannot match the hosted one. The same variable seeds the `secret_key` vault entry, which is what keeps the local database and the local functions agreeing on one value.

**Edge functions are deployed by CI** ([staging.yml](.github/workflows/staging.yml), [production.yml](.github/workflows/production.yml)) alongside `supabase db push`. They were previously deploy-by-hand, which let a migration land against a stale function — a failure mode that is invisible, because `pg_net` swallows the resulting error and mail simply stops arriving.

### Auth emails (dormant)

With ORCID-only sign-in and `enable_confirmations = false`, Supabase GoTrue sends **no** auth email in normal operation — contact-email verification is handled by the application (see Authentication above), not GoTrue. The branded static templates in [supabase/templates/](supabase/templates/) and the `[auth.email.template.*]` / `[auth.email.smtp]` blocks in [supabase/config.toml](supabase/config.toml) are retained as scaffolding (and to cover any residual GoTrue-initiated mail), but are not part of the active email path. Verification and all other mail flow through the application `emails` pipeline and the `resend` function above.

## Database management

The schema is described in two places, both kept in sync:

- [supabase/schemas/](supabase/schemas/) — declarative schema files, one per table. **Authoritative.** DESIGN.md links here. RLS policies live in the same file as the table definition.
- [supabase/migrations/](supabase/migrations/) — timestamped migration history. Required for every schema change.

Workflow for a schema change:

1. Write a migration in `supabase/migrations/`.
2. Update the matching declarative file in `supabase/schemas/`.
3. Run `npm run reset` locally to rebuild the DB and regenerate `src/data/database.ts`.

`src/data/database.ts` is generated by `npm run types` (`supabase gen types typescript --local`). Never edit it by hand.

RLS is enabled on every table. RLS policies are verified by an adversarial pgTAP test suite under [supabase/tests/](supabase/tests/) — one file per table, run with `npm run test:rls` (`supabase test db`). [.github/workflows/rls.yml](.github/workflows/rls.yml) runs it on every pull request and gates the staging/production deploys ([#79](https://github.com/reciprocalreviews/reciprocalapp/issues/79)).

### Submission completion

Submission completion is a guarded action implemented by the `mark_submission_done(submission_id, payment_template, mint_template)` RPC ([supabase/migrations/20260517000000_mark_submission_done.sql](supabase/migrations/20260517000000_mark_submission_done.sql)). It authorizes only priority-0 editors of the submission, validates that every approved non-editor assignment is already completed, and — in one atomic action — compensates every uncompleted priority-0 assignment, flips `submissions.status` to `done`, and stamps `submissions.completed_at`. If the venue cannot cover the total editor payout, it records a single proposed mint sized to the shortfall and returns without changing status; if there are pending non-editor assignments, it returns the blocker list without changing anything.

To enforce this gate, the table-level UPDATE grant is removed from the `authenticated` role and re-granted only on the editable columns — omitting `status` and `completed_at`. (A column-level `REVOKE` alone is a no-op while a table-wide `GRANT ALL` confers UPDATE on every column, so the grant must be narrowed, not merely revoked.) The RPC is `SECURITY DEFINER`, so it is the only path that can write these columns. The result: **done is terminal** — once set there is no API path to revert it, by design.

The same pattern makes `transactions` an immutable record, on both sides of a row's life. The table-level UPDATE is revoked and re-granted only on `status`, `tokens`, and the decline fields, locking the identity columns. INSERT is narrowed the same way — re-granted only on the columns a caller may legitimately supply, omitting `id` and `created_at` — so a client can propose a transaction but cannot choose its identity or backdate its place in history. DELETE is denied outright: the policy named `"transactions cannot be deleted"` previously had a `USING` clause that in fact *granted* deletion to any minter of the currency, so a minter could erase approved transfer history while the tokens those rows described stayed put, leaving tokens with no account of how they got where they are.

Per-editor compensation amounts come from `compensation(role, submission_type)`; multi-editor submissions are supported and all priority-0 editor assignments are paid in the same transaction. The RPC returns a structured JSONB result (`completed | blocked | insufficient`) that the application layer narrows with a runtime type guard before dispatching `WorkCompensated` emails (per-recipient, surfaced as notification banners via the `handle()` feedback channel).

### Resubmission links and per-type cost

A submission records its predecessor two ways: `submissions.previous` is an internal foreign key (`on delete set null`) to another submission, preferred wherever the chain is displayed; `submissions.previousid` is the legacy free-text external manuscript ID, retained for predecessors not on the platform (and matched against `externalid` within the same venue only as a fallback). Individual submissions set `previous` from a dropdown of the author's own prior submissions in the venue — choosing one mirrors its external ID into the (then read-only) `previousid` field **and auto-selects the matching revision submission type** (the `submission_types` row whose `revision_of` points at the predecessor's type). A typed external ID that matches one of the author's priors does the same best-effort. `bulk_import_submissions` best-effort resolves each row's `previousid` to an on-platform `previous` (exact `externalid` match within the venue).

Submission cost is **per submission type**: `submission_types.submission_cost` (`not null default 0`); there is no venue-wide submission cost. Each type is a different amount of work, so a resubmission — being its own revision type — simply carries its own cost; no separate resubmission cost exists. Admins edit a type's cost in the submission types table on the venue dashboard. The new-submission form charges the selected type's cost, and the bulk-import RPC sizes the mint by summing each row's submission type cost.

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
[unit-tests, playwright, locale-validation, rls-tests]   ── parallel
              │
              ▼ (prod: all pass · staging: not gated)
           migrate         ── supabase db push
              │
              ▼
           vercel          ── vercel pull → build → deploy
```

Migrations are applied before the Vercel deploy so schema changes are in place before the code that depends on them goes live.

- `main` → [.github/workflows/production.yml](.github/workflows/production.yml) deploys to Vercel **production** against the production Supabase project. Here `migrate`/`vercel` **gate on the tests** — if any test fails, neither the migration nor the deploy runs.
- `dev` → [.github/workflows/staging.yml](.github/workflows/staging.yml) deploys to a Vercel **preview** environment against the staging Supabase project. Staging is a throwaway test target, so its deploy is **not gated** on the tests: they still run in parallel for signal, but a red e2e/unit/rls run won't block the preview (it keeps deploys fast and lets the slow e2e suite finish out-of-band). The gate is what keeps a broken change from reaching `main`/production.

Required GitHub secrets: `SUPABASE_ACCESS_TOKEN`, `STAGING_DB_PASSWORD`, `STAGING_PROJECT_ID`, `PRODUCTION_DB_PASSWORD`, `PRODUCTION_PROJECT_ID`, `TEST_ENV`, `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`. Per-environment runtime config (Supabase URL, anon key, Resend key, etc.) lives in Vercel's environment variable settings and is pulled at build time by `vercel pull`.

## Testing

- **Unit.** Vitest. Files matching `src/**/*.unit.ts`. Run with `npm run test:unit`.
- **Integration.** Playwright, Chromium only. Files in `end2end/`. Run with `npm run test:end` — it brings up its own stack via `emu` (`sync` → `build` → `start:test` → `preview`), so no manual setup is needed. `start:test` deliberately excludes the edge runtime: nothing in `end2end/` needs it, because every email assertion reads the `emails` table directly with the `sql()` helper (the verification token is pulled out of `emails.args`) rather than a delivered message, and `send_email()`'s pg_net POST is best-effort and swallows its own failure. **CI and local run the identical command**, which is what stops the two from drifting — they used to differ, and the local variant chained `npm start`, whose trailing `supabase functions serve` blocks forever, so `vite preview` never started and the suite timed out after ten minutes while CI stayed green. If you want mail logged to the console while developing, run `npm start` in a separate terminal.
- **Combined.** `npm test` runs end2end then unit.

E2E specifics:

- **Shared seed, shared helpers.** All specs share the one Supabase DB seeded by [supabase/seed.sql](supabase/seed.sql); use the `SEED` constants and `sql()` helper from [end2end/test-utils.ts](end2end/test-utils.ts) rather than re-declaring UUIDs or `psql` wrappers. Restore any shared row you mutate (usually in a `finally`). [end2end/global-setup.ts](end2end/global-setup.ts) resets the DB before each local run, so no manual `npm run reset` is needed.
- **Hydration barrier.** Keep `waitForLoadState('networkidle')` before a Svelte interaction (card-expand click, bound `fill`) — on this SSR app the page looks ready before handlers are wired, so an early click is silently dropped. Only safe to drop before a pure assertion.
- **Auth** in tests uses a local-only email+password grant against the seeded users (`login()`/`logout()` in [src/routes/login.ts](src/routes/login.ts)); the seed gives every user a known password. The dev sign-in forms render only when `PUBLIC_SUPABASE_URL` points at a local stack — **not** merely when `PUBLIC_ENV !== 'prod'`. Staging is non-prod but points at a hosted project, and it is the one environment that can validate custom OIDC before production, so it must exercise the real ORCID path rather than a mock (and not accumulate throwaway `@orcid.example` users). ORCID custom OIDC can't run in local Supabase, so the real redirect/callback is exercised only in hosted staging against the ORCID sandbox.
- **New-account onboarding** is seen locally via a dev-only **mock** ORCID sign-in: off-production the login button calls `SupabaseAuth.signInWithMockORCID()`, which does a client `signUp` (local `enable_signup` on, `enable_confirmations` off → immediate session) with the ORCID iD/name in user metadata, so `handle_new_scholar` creates a scholar with `orcid`/`name` and a null email — the same state a real first sign-in produces. It is never rendered in production.
- **CI** ([.github/workflows/playwright.yml](.github/workflows/playwright.yml)) shards across a runner matrix (`--shard`), each shard its own fresh Supabase. Resize via `SHARD_TOTAL` + the `matrix.shard` list (keep in sync); floor is per-runner setup + the slowest single file. Supabase images are cached; `merge-reports` stitches shard blobs into one HTML report on failure; `retries: 2`.

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
