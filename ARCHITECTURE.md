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
  dr/                       Disaster recovery: dump.sh, manifest.sql
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

Each RPC that moves tokens also publishes the transaction id responsible through the `app.txn` GUC immediately before the write, and clears it immediately after, so the token ledger can record *why* each movement happened — see [Token ledger](#token-ledger). Four of them — `mint_tokens`, `transfer_tokens`, `complete_assignment`, and the per-editor loop in `mark_submission_done` — move tokens before the transaction row exists, so they generate its id up front with `gen_random_uuid()` and insert it explicitly rather than taking it from `returning id`. `approve_transaction` already receives the id as a parameter, and `create_submission` writes each author's charge before moving that author's tokens, so both set the GUC from an id they already hold. The two loops set it per iteration, not once per call: each author charge and each editor payout is a separate transaction, and one GUC for the whole function would file every movement under the last id.

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

**CI enforces that `schemas/` really is authoritative** ([ci.yml](.github/workflows/ci.yml)): it applies the migrations, applies the declarative files to a shadow database, and fails on any difference. Without that the claim decays silently — and it had. Turning the check on for the first time found eight stale function definitions (including `send_email` and `handle_new_scholar`, still carrying pre-`20260720010000` bodies), three stale policies, an index the migrations had dropped, three missing columns, two missing constraints, four RPCs, and the `on_auth_user_created` trigger that is the only path by which a scholar row is ever created.

Most seriously, it found that **the declarative files could not be applied at all**: `assignments.sql` references `preference_levels` but `[db.migrations].schema_paths` listed it first, so the set failed on a foreign key. Nothing had ever tried. `schema_paths` is now in dependency order — a file may only reference tables declared above it — with `audit_log` and `reconciliations` last, since their triggers attach to everything above.

This is not only a documentation concern. A restore applies the schema from migrations while [RECOVERY.md](RECOVERY.md) points at `schemas/` to explain what should be there; a schema description that is wrong, or that will not load, fails exactly when someone is depending on it.

RLS is enabled on every table. RLS policies are verified by an adversarial pgTAP test suite under [supabase/tests/](supabase/tests/) — one file per table, run with `npm run test:rls` (`supabase test db`). [.github/workflows/rls.yml](.github/workflows/rls.yml) runs it on every pull request and gates the staging/production deploys ([#79](https://github.com/reciprocalreviews/reciprocalapp/issues/79)).

### Submission completion

Submission completion is a guarded action implemented by the `mark_submission_done(submission_id, payment_template, mint_template)` RPC ([supabase/migrations/20260517000000_mark_submission_done.sql](supabase/migrations/20260517000000_mark_submission_done.sql)). It authorizes only priority-0 editors of the submission, validates that every approved non-editor assignment is already completed, and — in one atomic action — compensates every uncompleted priority-0 assignment, flips `submissions.status` to `done`, and stamps `submissions.completed_at`. If the venue cannot cover the total editor payout, it records a single proposed mint sized to the shortfall and returns without changing status; if there are pending non-editor assignments, it returns the blocker list without changing anything.

To enforce this gate, the table-level UPDATE grant is removed from the `authenticated` role and re-granted only on the editable columns — omitting `status` and `completed_at`. (A column-level `REVOKE` alone is a no-op while a table-wide `GRANT ALL` confers UPDATE on every column, so the grant must be narrowed, not merely revoked.) The RPC is `SECURITY DEFINER`, so it is the only path that can write these columns. The result: **done is terminal** — once set there is no API path to revert it, by design.

The same pattern makes `transactions` an immutable record, on both sides of a row's life. The table-level UPDATE is revoked and re-granted only on `status`, `tokens`, and the decline fields, locking the identity columns. INSERT is narrowed the same way — re-granted only on the columns a caller may legitimately supply, omitting `id`, `created_at`, and `seq` — so a client can propose a transaction but cannot choose its identity, backdate it, or pick its place in the order. DELETE is denied outright: the policy named `"transactions cannot be deleted"` previously had a `USING` clause that in fact *granted* deletion to any minter of the currency, so a minter could erase approved transfer history while the tokens those rows described stayed put, leaving tokens with no account of how they got where they are.

Column grants cannot express a rule that depends on the row's *current* state, and two such rules matter, so a `BEFORE UPDATE` trigger carries them ([20260808030000](supabase/migrations/20260808030000_transactions_immutable.sql), error code `RR005`):

- **A decision is final.** `status`, `tokens`, `decliner` and `decline_reason` are writable because a proposed transaction has to become approved or declined — and nothing stopped that happening twice. An approved transfer, tokens already moved and recorded in `token_events`, could be flipped to `declined` afterwards, leaving the ledger saying value moved and the transaction saying it was refused.
- **The amount cannot be resized.** There is no amount column; the amount *is* `cardinality(tokens)`. Since `tokens` is writable, the amount was writable: a proposed row carrying N placeholders could be approved with a different number of real ids. Every legitimate path already preserved the count — `approve_transaction` sizes its work from `cardinality(_txn.tokens)` — so this makes a habit into a rule. Filling placeholders in at the same count remains allowed, since that is what approval is.

A trigger rather than a policy or a grant, because those decide by *who* is asking while this decides by what the row already is, and it must bind the `SECURITY DEFINER` RPCs and anyone at a psql prompt equally. A restore is unaffected: data loads under `session_replication_role = replica`, so historical rows are not judged against rules they predate.

`seq` is a `bigint` from a sequence, and it is what makes the order of history well-defined. `created_at` defaults to `now()`, which is transaction *start* time, so every row a single RPC writes carries an identical timestamp — `create_submission` inserts one charge per author that way. Sorting on `created_at` alone therefore leaves ties the planner may break differently per query, and a `LIMIT`/`OFFSET` over an unstable sort can return one row on two pages while skipping another; the three paginated transaction lists all sort `created_at desc, seq desc` for this reason. Note that a sequence gives *insertion* order rather than *commit* order, so anything treating `seq` as a replication watermark should compare against `pg_snapshot_xmin(pg_current_snapshot())` instead of assuming `max(seq)` is final.

Per-editor compensation amounts come from `compensation(role, submission_type)`; multi-editor submissions are supported and all priority-0 editor assignments are paid in the same transaction. The RPC returns a structured JSONB result (`completed | blocked | insufficient`) that the application layer narrows with a runtime type guard before dispatching `WorkCompensated` emails (per-recipient, surfaced as notification banners via the `handle()` feedback channel).

### Two rules that look like one: approving an assignment

There are two distinct authorization questions here, and they were easy to confuse because one of them used to be named as if it were the other.

- **`can_approve_assignment(submission, role)`** ([20260816010000](supabase/migrations/20260816010000_can_approve_assignment.sql)) is the approval rule: a venue admin, or the holder of an **approved assignment on this submission** for either the venue's priority-0 role or the role that approves the one in question. `complete_assignment` calls it, so the enforcing copy exists once. [src/lib/data/canApproveAssignment.ts](src/lib/data/canApproveAssignment.ts) is the UI-gating mirror; the two are pinned to the same table of cases by [canApproveAssignment.unit.ts](src/lib/data/canApproveAssignment.unit.ts) and by the `create_submission`/`complete_assignment` cases in [atomic_crud_rpc.sql](supabase/tests/rpc/atomic_crud_rpc.sql).
- **`isRoleApproverVolunteer(role)`** (formerly `isApprover`) asks something else entirely: is the caller an **accepted volunteer** on the role that approves this one, anywhere in the venue? It reads `volunteers`, takes no submission, and has no admin or priority-0 branch. It is the `USING` clause of the assignments UPDATE policy, where an AE must be able to approve a bid on a submission they hold no assignment on.

They disagree in both directions — an accepted approver with no assignment satisfies the second and not the first; a venue admin satisfies the first and not the second — so unifying them is a permissions change, not a refactor. Narrowing `isRoleApproverVolunteer` to match the approval rule would silently revoke UPDATE from every AE approving a bid, breaking bidding. It therefore keeps its behaviour and loses its misleading name. A third near-copy, in `SupabaseCRUD.requestCompensation`, picked email recipients by a rule that omitted the priority-0 editor branch and treated admins as a fallback rather than a first-class branch, so the two people most able to act on a compensation request were often the two who never heard about it; it now uses the same three-branch union.

### Resubmission links and per-type cost

A submission records its predecessor two ways: `submissions.previous` is an internal foreign key (`on delete set null`) to another submission, preferred wherever the chain is displayed; `submissions.previousid` is the legacy free-text external manuscript ID, retained for predecessors not on the platform (and matched against `externalid` within the same venue only as a fallback). Individual submissions set `previous` from a dropdown of the author's own prior submissions in the venue — choosing one mirrors its external ID into the (then read-only) `previousid` field **and auto-selects the matching revision submission type** (the `submission_types` row whose `revision_of` points at the predecessor's type). A typed external ID that matches one of the author's priors does the same best-effort. `bulk_import_submissions` best-effort resolves each row's `previousid` to an on-platform `previous` (exact `externalid` match within the venue).

Submission cost is **per submission type**: `submission_types.submission_cost` (`not null default 0`); there is no venue-wide submission cost. Each type is a different amount of work, so a resubmission — being its own revision type — simply carries its own cost; no separate resubmission cost exists. Admins edit a type's cost in the submission types table on the venue dashboard. The new-submission form charges the selected type's cost, and the bulk-import RPC sizes the mint by summing each row's submission type cost.

`create_submission` enforces that the author charges add up to that cost (`RR007`) and that no author is listed twice (`RR008`) ([20260816000000](supabase/migrations/20260816000000_submission_cost_and_authors.sql)). Both rules previously lived only in the new-submission form, so they held for callers who came through the form and for no one else — anything reaching the RPC directly could name its own price, and a duplicated author was charged twice for one manuscript because the RPC's loop indexes the authors array positionally. Neither can be a `CHECK` constraint: the cost rule spans two tables, and the duplicate rule must not apply to bulk-imported submissions, which arrive by a different path with no payments. The same call also verifies that the submission type belongs to the venue being submitted to, which was never checked. `src/lib/data/charges.ts` is the client half, so the form can refuse before the round trip rather than instead of it.

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

Two steps run immediately before `supabase db push`, because a bad migration is the likeliest cause of data loss and the one moment you know is coming. The first records the append-only watermarks into the job summary, which makes "restore to just before the deploy" a precise instruction — wall-clock cannot express it when a deploy and user activity interleave. The second refuses to push when production carries migrations this repository does not, so a hand-applied change is reconciled rather than silently overwritten.

- `main` → [.github/workflows/production.yml](.github/workflows/production.yml) deploys to Vercel **production** against the production Supabase project. Here `migrate`/`vercel` **gate on the tests** — if any test fails, neither the migration nor the deploy runs.
- `dev` → [.github/workflows/staging.yml](.github/workflows/staging.yml) deploys to a Vercel **preview** environment against the staging Supabase project. Staging is a throwaway test target, so its deploy is **not gated** on the tests: they still run in parallel for signal, but a red e2e/unit/rls run won't block the preview (it keeps deploys fast and lets the slow e2e suite finish out-of-band). The gate is what keeps a broken change from reaching `main`/production.

Required GitHub secrets: `SUPABASE_ACCESS_TOKEN`, `STAGING_DB_PASSWORD`, `STAGING_PROJECT_ID`, `PRODUCTION_DB_PASSWORD`, `PRODUCTION_PROJECT_ID`, `TEST_ENV`, `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`. Per-environment runtime config (Supabase URL, anon key, Resend key, etc.) lives in Vercel's environment variable settings and is pulled at build time by `vercel pull`.

## Change history

Two append-only logs record what changed and why: [token_events](supabase/schemas/token_events.sql) for the token economy, and [audit_log](supabase/schemas/audit_log.sql) for everything else. They share their design — trigger-captured, foreign-key-free, append-only by trigger, invisible to the API, absent from realtime — and differ only in shape.

### token_events

An append-only record of every change of token ownership. It exists because neither of the two tables that look like they should provide one actually does.

`public.tokens` is the **state**: one row per token, and a transfer is an in-place `UPDATE` of its `scholar`/`venue` columns. It has no `created_at`, no history, no versioning — so once ownership is overwritten the previous owner is gone from the database entirely. Balances are `count(*)` over that table, which means the current balance is the only thing the schema knows.

`public.transactions` looks like the ledger and is not. Nothing derives from it and it derives from nothing: it has no amount column (the amount is `cardinality(tokens)`), its `tokens` array is rewritten from placeholder UUIDs to real ids on approval, and it records an *assertion* about who paid rather than an *observation* of what moved. It stays in step with reality only by convention inside the RPCs.

`token_events` is the observation. Four decisions shape it:

- **Capture is a trigger on `tokens`, not logging inside the RPCs.** A trigger sits below RLS and below the RPC boundary, so it catches every path — the RPCs, a direct PostgREST write, a `service_role` script, manual psql surgery during an incident, and a restore. Logging inside the RPCs would require believing every write goes through them, which is exactly the belief that proved false when `tokens` turned out to be directly writable from the browser. Completeness by construction is the point.
- **Attribution flows through the `app.txn` GUC.** Each RPC publishes the relevant transaction id immediately before touching `tokens` and clears it immediately after, so `select count(*) from token_events where op = 'move' and txn is null` is **zero in a healthy system**. Anything else is value that moved with no transaction explaining it. Clearing matters as much as setting: without it, an unattributed write later in the same database transaction would silently borrow the previous id and the alarm would read clean while being wrong.
- **No foreign keys**, deliberately. A log constrained by the rows it describes cannot outlive them, and `scholars.id` cascades from `auth.users` — so an accidental account deletion would delete the evidence of itself. FK-free is what lets the log survive a cascade and what lets a reconciler *detect* one.
- **Append-only is enforced by a trigger, not RLS**, because `postgres` and `service_role` bypass policies and are exactly who would be at the keyboard during an incident. The single sanctioned mutation is erasure, which nulls `scholar`/`prev_scholar`/`actor` under an explicit `app.erasure` flag and leaves the movement intact, so balances stay reconstructible after a scholar exercises their right to be forgotten.

`tokens_as_of(timestamptz)` replays the log to reconstruct ownership at any past instant. Diffing it against `tokens` turns "we discovered on Thursday that Tuesday's deploy corrupted balances" into a targeted repair instead of a restore that discards two days of legitimate work. **Mind the clock**: `token_events.at` is `clock_timestamp()`, which advances during a transaction, while `now()` is transaction *start* time — so `tokens_as_of(now())` called from inside the transaction that just wrote events silently omits them. The argument defaults to `clock_timestamp()` for that reason; pass an explicit timestamp only when you mean the past.

The table is **not** in the `supabase_realtime` publication — a 500-token mint would fan 500 rows out to every connected client, each firing `invalidateAll()` — and it is readable only by `service_role`. Historical token ownership is not exposed anywhere in the product, and would leak reviewing activity that venue anonymity settings exist to protect.

Behaviour is covered by [supabase/tests/invariants/token_events.sql](supabase/tests/invariants/token_events.sql), which asserts the properties the design rests on against real RPC calls: capture, attribution, that a deliberate out-of-band write shows up unattributed, that `tokens_as_of()` reproduces `tokens` exactly, and that each token's chain of previous owners is unbroken.

### audit_log

The general counterpart, covering the 15 mutable state tables plus `transactions`. Each row holds the whole `before` and `after` as `jsonb`, the acting scholar, and the transaction id that wrote it. Two things motivate it:

- **Forensics.** `venues.admins`, `currencies.minters`, and `scholars.steward` are privilege-bearing columns edited by read-modify-write on an array — lossy under concurrency and invisible afterward. Nothing else can say when someone gained admin on a venue, or who granted it. `transactions` is included for the same reason: the row records who *declined* a transaction but never who approved it.
- **Recovery point.** Without PITR, a nightly dump means up to 24h of loss. Replaying `after` in `seq` order lets a restore catch up from the dump instead, and ordering by `seq` respects foreign-key causality for free, because the original writes did.

Four tables are excluded deliberately: `tokens` (covered by `token_events` in a shape ~4× smaller, and it is the highest-volume table in the schema), `emails` (already immutable, and auditing it would store every rendered message body twice), `email_verifications` (holds a sha256 token hash — copying a credential-like value into a longer-lived table widens its exposure for nothing), and the two logs themselves.

Whole-row payloads rather than deltas, because replay is then an upsert rather than a merge, and correctness matters more than storage at this volume. **No-op updates are skipped** — the app calls `invalidateAll()` after every write and several components re-save unchanged values, which is the difference between a usable log and noise.

One consequence worth holding onto: because the payloads are whole rows, this table contains scholars' contact emails and the bodies of author thank-you notes, making it strictly more sensitive than any single table it records. `forget_scholar()` will have to scrub here as well as in `token_events` and `transactions`.

### reconcile_ledger

The logs make corruption *findable*; [reconcile_ledger()](supabase/migrations/20260808010000_reconcile_ledger.sql) makes it *found*. It runs nightly via `pg_cron`, records every run in `public.reconciliations`, and on failure raises a warning into the Postgres log and emails the stewards.

Six checks decide `ok`, and each answers a question nothing else in the schema can:

| Check | Catches |
|---|---|
| `unattributed_moves` | Value that moved with no transaction explaining it — a bug, a careless migration, or someone moving balances by hand |
| `replay_mismatches` | The ledger no longer reproduces `tokens` |
| `chain_breaks` | A write that escaped the trigger, or a partial restore. Invisible to a state comparison, because the end state can still look right |
| `placeholders_in_approved` | An approved transaction still holding null-UUIDs: an amount recorded for a movement that never happened |
| `dangling_token_refs` | An approved transaction citing a token that is gone, or in another currency |
| `conservation_violations` | The two narratives disagreeing holder by holder — computed only when provenance is clean, since unexplained tokens would otherwise produce drift check 1 has already reported |

Two further signals are **advisory** and deliberately do not flip `ok`: `unattributed_mints` and `orphan_proposals`. Both are real signal in production and should be zero there, but [supabase/seed.sql](supabase/seed.sql) inserts tokens directly and ships one proposal with no supporters, so every development and CI database carries them permanently. Folding them into `ok` would make the check red everywhere and therefore ignored — which is the failure mode a monitoring check is most prone to.

Each check is covered by [supabase/tests/invariants/reconcile_ledger.sql](supabase/tests/invariants/reconcile_ledger.sql), which breaks the invariant deliberately and asserts the count moves. A checker that returns `ok` regardless is worse than none, because it actively reassures.

### Scheduled jobs

Two `pg_cron` jobs now run: `remind-daily` at 22:00 UTC and `reconcile-ledger` at 22:15, staggered so they never contend. Both live in `cron.job`, which is **cluster state outside every schema dump** — captured separately by [dump.sh](supabase/dr/dump.sh) into `cron.json` and by `quarantine.sql` before a restore. That is not theoretical: `remind-daily` was silently lost once by a `supabase db diff` run (see `supabase/migrations/20260517230819_restore_remind_cron.sql`).

## Data rights

The terms page has promised data portability and erasure since it was written; [20260808050000](supabase/migrations/20260808050000_erasure_and_export.sql) is the machinery behind them.

**Export** is `export_scholar_data()`, served as a download by [scholar/[id]/export/+server.ts](src/routes/[[lang]]/scholar/[id]/export/+server.ts). Authorization lives in the function rather than the route — `SECURITY DEFINER`, checking `auth.uid()` and letting a steward through for a request that arrives out of band — so a future CLI or support script cannot reach the data by going around the endpoint. The token history it includes is only possible because of `token_events`; before the ledger there was no record of where a scholar's tokens had been.

**Erasure is anonymisation in place, and that is forced by the data rather than chosen for convenience.** Fourteen tables reference `scholars(id)`, among them `transactions.creator`, which is `NOT NULL`. A scholar's participation is woven into other people's records: the transaction that paid a reviewer, the submission with co-authors, the thank-you note someone else received. Deleting the row would either fail on those constraints or destroy records belonging to other people. So the row survives as an anonymous tombstone — name, email, ORCID, free-text status, and the `auth.users` identity behind it are destroyed, and what remains is a uuid referring to nobody. That is what the terms already call transaction records being "de-linked".

Two things are deliberately **not** erased:

- **The ledger's ownership columns.** An earlier sketch proposed nulling `token_events.scholar` and `prev_scholar`. Doing so would corrupt the ledger outright: `tokens_as_of()` reconstructs ownership from exactly those columns, so the most recent event for each of the scholar's tokens would claim no owner, `reconcile_ledger()`'s replay check would fail, and the tokens would become unexplainable. They hold uuids, which refer to nobody once the tombstone is scrubbed. Only `actor` is nulled.
- **The tokens themselves.** They are currency rather than personal data, and moving them would silently change a venue's reserve.

Every erasure is recorded in `public.erasures`, which has no foreign key to `scholars` so it outlives the row it names and survives a restore that predates it. Re-applying that list is a mandatory step of every restore.

## Backups

The database is dumped nightly at 08:00 UTC by [.github/workflows/backup.yml](.github/workflows/backup.yml) to S3-compatible object storage we control, independent of Supabase. [RECOVERY.md](RECOVERY.md) is the operational document — provisioning, verification, and (from the next phase) the restore runbook. The mechanics live in [supabase/dr/dump.sh](supabase/dr/dump.sh), which is a standalone script rather than inline workflow steps so the nightly job, the pre-migration snapshot, and the rehearsal drill all capture byte-identical artifacts, and so it can be run from a laptop during an incident.

Four decisions worth knowing before touching any of it:

- **`pg_dump`, not `supabase db dump`.** The latter is scoped to the schemas it knows about, and this database is not restorable without `auth`: `public.scholars.id` references `auth.users(id) ON DELETE CASCADE`, so a `public`-only dump restores into a project with zero scholars. Custom-format archives are used throughout so a restore can be surgical (`pg_restore -t submissions`) instead of all-or-nothing.
- **Encryption is `age` in public-key mode.** Only the recipient's public key is in the repo; the private identity is held offline. The property that matters is that **CI can write backups but cannot read any backup, including the one it just made** — a compromised `GITHUB_TOKEN` yields nothing. `dump.sh` deletes its whole output directory if it fails before encryption completes, and the workflow independently refuses to upload anything that isn't `.age`.
- **Two pieces of state live outside every schema dump** and are captured on purpose: `cron.job` (exactly how `remind-daily` was silently lost once — see `supabase/migrations/20260517230819_restore_remind_cron.sql`) and the *names* of the vault secrets. Vault **values** are never captured; they are set by hand on hosted projects and belong in a password manager, not in an artifact CI can write.
- **Erasures must be re-applied after every restore.** A backup taken before someone asked to be forgotten still contains them, so a restore quietly recreates data the platform said it had destroyed — a broken promise created by the recovery itself, and one nobody would notice. [reapply-erasures.sql](supabase/dr/reapply-erasures.sql) replays `public.erasures` over the restored database; it is safe to run repeatedly, because `forget_scholar` only ever removes.
- **The manifest is what makes a restore checkable.** It records exact per-table row counts, the `auth.users` count, append-only watermarks — which populate for `token_events`, `audit_log`, and `transactions.seq`, so a backup states exactly how far each log had advanced, the value a replay-forward restore keys off — the applied migration list, extensions, the realtime publication membership, the RLS policy count, and a SHA-256 of every artifact. A restore that doesn't match it is a failed restore. It is written defensively, so the columns the ledger phase adds appear automatically and their absence today is not an error.

Restores are scripted rather than improvised. [supabase/dr/quarantine.sql](supabase/dr/quarantine.sql) neutralizes the three ways a restore reaches real people — the `emails` send trigger, the `remind-daily` cron job, and the realtime publication — and records what it changed so [rearm.sql](supabase/dr/rearm.sql) can reverse it from captured state rather than a hardcoded list that goes stale. [drill.sh](supabase/dr/drill.sh) restores a real backup and asserts the result against the manifest, and [.github/workflows/backup-drill.yml](.github/workflows/backup-drill.yml) runs it monthly.

The first drill found something worth knowing: **a bare Postgres database is not a valid restore target.** Restoring into one succeeded, matched every row count, and silently produced a database with 29 of 71 RLS policies missing, because every policy calls `auth.uid()` and the `auth` schema did not exist. Row counts alone would have called that a success. `drill.sh` now refuses such a target up front. The operational consequence is in [RECOVERY.md](RECOVERY.md); the architectural one is that this schema is not portable to plain Postgres — it depends on Supabase's `auth` schema at the policy level, not merely at the application level.

Point-in-time recovery is **not** enabled. Instead the append-only logs do the same job for a fraction of the cost, which is what they were built for: [tail.sh](supabase/dr/tail.sh) exports `audit_log` and `token_events` hourly — a few kilobytes, because they are the only tables a restore needs to catch up on — and [replay.sql](supabase/dr/replay.sql) applies them over a restored dump via `replay_audit_log()`. That takes the recovery point from **24 hours to roughly one**, and it is demonstrated rather than assumed: restoring a nightly dump alone loses the changes made after it, and replaying the tail brings them back to exactly the prior state.

One ordering rule matters enough to state here. **Replay must happen before anything else writes, including before re-arming.** `seq` is an identity column, so after a restore it resumes from the restored maximum and any intervening write takes the very numbers the tail is carrying; deduplicating on `seq` would then discard the tail's real rows as duplicates. `rearm.sql`'s reminder stamping is enough to trigger this, and did on the first test — the replay reported success having applied the wrong rows. `replay.sql` now refuses to run when `audit_log` has moved past the watermark.

## Testing

- **Unit.** Vitest, node environment, no DOM. Files matching `src/**/*.unit.ts`, co-located with the module under test. Run with `npm run test:unit`.

  There is no component-testing setup, and the unit layer is not the place to re-test what the pgTAP suites and Playwright already cover. Its job is the pure logic in between — which means logic has to be **reachable** to be tested, and most of the interesting rules used to live inside `.svelte` files where nothing could import them. So the sort/filter and validation rules are extracted into plain modules that the components then import: [sortSubmissions.ts](src/lib/data/sortSubmissions.ts) (search matching, the author-visibility gate, payment status, the sort pipeline), [sortAssignees.ts](src/lib/data/sortAssignees.ts) (assignee and bid ordering), [charges.ts](src/lib/data/charges.ts), [bulkImportRows.ts](src/lib/data/bulkImportRows.ts), [toCSV.ts](src/lib/data/toCSV.ts), [canViewSubmission.ts](src/lib/data/canViewSubmission.ts), and [interpolate.ts](src/lib/locales/interpolate.ts) — the last being the single substitution pass every user-visible string goes through. Each takes its page's reactive reads as an explicit context argument (including `now`, so time-dependent rules are deterministic) rather than closing over them. When adding logic to a component that has a rule in it — an ordering, a permission, an arithmetic — put the rule in a module and let the component call it.
- **Integration.** Playwright, Chromium only. Files in `end2end/`. Run with `npm run test:end` — it brings up its own stack via `emu` (`sync` → `build` → `start:test` → `preview`), so no manual setup is needed. `start:test` deliberately excludes the edge runtime: nothing in `end2end/` needs it, because every email assertion reads the `emails` table directly with the `sql()` helper (the verification token is pulled out of `emails.args`) rather than a delivered message, and `send_email()`'s pg_net POST is best-effort and swallows its own failure. **CI and local run the identical command**, which is what stops the two from drifting — they used to differ, and the local variant chained `npm start`, whose trailing `supabase functions serve` blocks forever, so `vite preview` never started and the suite timed out after ten minutes while CI stayed green. If you want mail logged to the console while developing, run `npm start` in a separate terminal.
- **Combined.** `npm test` runs end2end then unit.
- **What gates a pull request.** `ci.yml` (generated types + schema drift), `rls.yml` (all pgTAP), `vitest.yml`, and `locales.yml`. The last two were `workflow_call`-only and so ran first on the push to `dev` — i.e. after review had already passed, which meant a unit test could not actually block the change it was written for. Neither needs Supabase or a browser, so gating on them costs about a minute. Playwright still runs only on the push to `dev`, where the shard matrix is worth its runtime.

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
