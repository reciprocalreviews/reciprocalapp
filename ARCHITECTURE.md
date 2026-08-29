# Architecture

_Last revised: 2026-08-28_

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
  brand/                    Logo, favicons, and social card; see its README
  robots.txt                Crawl policy; points at the generated /sitemap.xml
supabase/
  schemas/                  Authoritative declarative table schemas (one file per table)
  migrations/               Timestamped migration history
  functions/                Edge functions (Deno)
  dr/                       Disaster recovery: dump.sh, manifest.sql
  config.toml               Local Supabase config
end2end/                    Playwright integration tests
scripts/
  updates.js                Generates updates.json from CHANGELOG.md at build time
  icons.js                  Rasterizes static/brand/logo.svg into its PNG derivatives
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

That narrowing left `steward` writable by nobody, which was correct and also meant stewardship could only be conferred at a psql prompt. The tool that migration deferred — "a `SECURITY DEFINER` RPC gated on `isSteward()`, not a blanket table privilege" — is [set_steward](supabase/migrations/20260818000000_set_steward.sql), and the column grants are deliberately untouched, because they are what makes it the only path. Two guards protect the floor: nobody may demote themselves, so stepping down is always an act another steward performs; and the last steward may not be demoted at all. The second looks unreachable and is not — serially it is, since demoting X requires a steward caller other than X, so one always survives. It earns its place concurrently, and only alongside the row lock the function takes before deciding anything: under `READ COMMITTED` two stewards demoting each other would each see the other still standing, and both would succeed. Covered by [set_steward_rpc.sql](supabase/tests/rpc/set_steward_rpc.sql), which also re-asserts that the column grant is still narrow — if that ever passes, every guard above can be walked around.

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

**Every path that moves existing value goes through one function**, [`public._move_tokens`](supabase/schemas/tokens.sql) ([20260830000000](supabase/migrations/20260830000000_token_scaling_phase1.sql)). Six RPCs used to pick tokens with `select id from tokens where <holder> order by id limit N` and then move them with `update ... where id = any(_token_ids)` — no lock on the select, and no ownership predicate on the update. Under `READ COMMITTED` two concurrent draws on the same holder see the same snapshot and, because the order was `id` and therefore deterministic, select **the same rows**; the second update blocks on the first's row locks and then, since `id = any(...)` is still true once the first commits, overwrites them. Both callers report success and both write a `transactions` row, but the first recipient's tokens are gone. The holder's `count(*)` stays consistent, which is why nothing noticed — only `reconcile_ledger`'s conservation check would have caught it, a day later. Reproduced before the fix with a 50-token reserve and two sessions each drawing 25: both reported moving 25, and the first scholar ended up holding 0.

`_move_tokens` takes its rows `for update skip locked` and re-asserts the source's ownership in the `UPDATE` itself. `SKIP LOCKED` rather than a plain `FOR UPDATE` because blocking would serialize every payout in a busy venue behind one another; skipping makes concurrent draws disjoint and turns `RR003` from "the holder lacks the tokens" into "the holder lacks _available_ tokens", which is the accurate claim and is retryable. It also carries no `ORDER BY`: tokens are fungible, so the ordering pinned nothing observable, while making concurrent draws contend for exactly the same lowest ids and talking the planner out of the composite indexes onto a `tokens_pkey` walk past every token already spent — 35ms per transfer on a 500,000-token fixture against 0.05ms without it. **A seventh token-moving RPC must call `_move_tokens` rather than reimplement the select-then-update.** [supabase/tests/rpc/move_tokens_rpc.sql](supabase/tests/rpc/move_tokens_rpc.sql) pins the contract, including a structural assertion that the locking clause is still there.

Balances are `count(*)` over `tokens`, and the app used to read them by fetching one row per token and taking the array length in the browser. PostgREST caps a response at `max_rows` (1000) and truncation is not an error, so those counts silently stopped at 1000: a quarter-million-token reserve reported 1000, and the affordability check refused submissions their authors could pay for. Counting now happens in the database — `currency_holder_counts`, `scholar_balances`, and `{ count: 'exact', head: true }` at the call sites.

`_welcome_volunteer` (the helper behind `create_volunteer` / `accept_role_invite`) moves real tokens rather than recording a proposal. It used to insert a _proposed_ venue→scholar transaction of placeholder UUIDs for a minter to approve later, which contradicted DESIGN's "minted and given" and put a human approval between a newcomer and the tokens they had just volunteered to earn — most painfully for someone volunteering in order to afford a submission. It now mirrors `approve_transaction`'s venue-source branch: draw from the venue's reserve, mint only the shortfall into the reserve first, move the tokens, and record one **approved** transaction. Both token writes are attributed through `app.txn`, so the grant explains itself in the ledger like every other movement. It returns the number of tokens granted (0 on each no-op path) and both callers pass that back as `welcome_granted`, so the confirmation can state the amount instead of promising tokens that may never have been granted — the three conditions that decide it are not ones the client can evaluate without re-deriving the rule. Changing a function's return type is not something `create or replace` will do, so the migration drops it first. The first of those conditions is scoped to the venue: `create_volunteer` and `accept_role_invite` count the scholar's existing volunteer rows through a join on `roles.venueid`, because `welcome_amount` is one venue's standing policy in one venue's currency. They previously counted volunteer rows platform-wide, so a scholar who had ever volunteered anywhere received nothing at every venue they joined afterward — silently, since the grant's only outward sign is the amount in the confirmation.

Each RPC that moves tokens also publishes the transaction id responsible through the `app.txn` GUC immediately before the write, and clears it immediately after, so the token ledger can record _why_ each movement happened — see [Token ledger](#token-ledger). Five of them — `mint_tokens`, `transfer_tokens`, `complete_assignment`, `_welcome_volunteer`, and the per-editor loop in `mark_submission_done` — move tokens before the transaction row exists, so they generate its id up front with `gen_random_uuid()` and insert it explicitly rather than taking it from `returning id`. `approve_transaction` already receives the id as a parameter, and `create_submission` writes each author's charge before moving that author's tokens, so both set the GUC from an id they already hold. The two loops set it per iteration, not once per call: each author charge and each editor payout is a separate transaction, and one GUC for the whole function would file every movement under the last id.

For tokens, the RPCs are not merely the preferred path but the **only** one. `INSERT`, `UPDATE`, and `DELETE` on `public.tokens` are revoked from `authenticated` and `anon`, so a direct PostgREST write fails with `42501`; the remaining policies are explicit denials that document the intent and let the pgTAP suite assert it. This closed a hole in which the owning scholar could `PATCH /rest/v1/tokens` and reassign a token to anyone with **no `transactions` row written at all** — and, because the UPDATE policy's `WITH CHECK` was `true` and so pinned nothing about the resulting row, could also rewrite a token's `currency` and counterfeit value in a currency they were never granted (a balance is `count(*)` of token rows in that currency). Because the RPCs are `SECURITY DEFINER` and owned by `postgres`, the revoke does not touch them.

## Realtime

Pages stay live by subscribing to Postgres change feeds. The wrapper is [src/lib/data/SupabaseRealtime.ts](src/lib/data/SupabaseRealtime.ts):

```ts
getRealtimeChannel(name, supabase, [{ table, filter }, ...], () => invalidateAll());
```

Each subscription declares the tables and row filters it cares about; the callback usually calls `invalidateAll()` to retrigger SvelteKit's load functions. Routes that depend on shared mutable state should add a channel rather than polling.

**Subscribe to `transactions`, never to `tokens`.** `tokens` holds one row per token, so moving N tokens emits N `postgres_changes` messages to every client watching that venue or that scholar, and each one re-runs every load function on their page: a 50-token welcome grant fired fifty full page refetches at the recipient, and minting a community's supply would fire a quarter of a million at everyone on the venue. [token_events.sql](supabase/schemas/token_events.sql) had always carried that reasoning as its explanation for staying out of the publication — "a 500-token mint would fan 500 rows out to every connected client, each firing `invalidateAll()`" — and it was equally true of `tokens`, which was in it. `tokens` was removed in [20260830010000](supabase/migrations/20260830010000_token_scaling_phase2.sql). Nothing is lost: only a transaction can move a token, so the `transactions` filters wake on exactly the same events, one row per movement whatever the amount.

`reloadOnChanges` also debounces, coalescing a burst into a single `invalidateAll()`. One user-visible action routinely writes several rows — a submission inserts a charge per author, an editor payout writes a transaction per editor — and each arrived as its own message.

A consequence to be aware of: `handle()` also calls `invalidateAll()` after every successful write, and realtime callbacks land asynchronously after a write commits. Any component that holds in-progress user input (a partially-typed field, an open form) must keep a local working copy of that input and only sync from the load-function prop when it isn't actively editing — otherwise the next refetch will overwrite the user's input. [src/lib/components/EditableText.svelte](src/lib/components/EditableText.svelte) is the canonical example of this pattern.

`handle()` **awaits** that `invalidateAll()`, so it resolves only once the load functions have rerun and the page data reflects the write. That matters to anything that reads a prop straight after saving: while it returned early, every caller was handed "success" while its props were still the pre-write values, and a component that synced from them at that moment showed the old text until the refetch landed and then flipped to the new one. Because the data is current by the time the promise settles, a component may take its value back from the prop on success — which is also how it learns when the server kept something other than what was typed, as `VerifyEmail` does by leaving the stored address alone until the new one is verified.

## Email pipeline

Email is **application email** — transactional, reminder, and contact-email verification — all sharing one branded visual identity, and all replyable: a send carries `Reply-To: stewards@reciprocal.reviews` (see Addresses below) unless the row names its own, which currently only the new-volunteer notice does. The branded footer follows the header rather than repeating a fixed sentence, so a message that replies to a person says so and names `stewards@` separately as the route to support; `renderBrandedEmail`'s `replyTo` argument is trailing and optional, so the `remind` cron keeps the default without changing. (Supabase GoTrue no longer sends auth email: sign-in is ORCID and email verification is app-level, so the auth-email path is dormant — see below.) Templates are English only: there is no mechanism yet to solicit a scholar's language preference.

### Application emails

Server code never calls Resend directly. The producer / consumer split is:

1. **Producer.** Application code calls `emailScholars(scholars, templateKey, args)` (in [SupabaseCRUD](src/lib/data/SupabaseCRUD.svelte.ts)), which goes through the `queue_email` RPC. **Direct INSERT into `emails` is revoked** from `authenticated` and `anon`: inserting a row sends branded mail, so an insert policy meant any signed-in user could name any recipient with any body — an open relay from `notifications@reciprocal.reviews`, and self-service ORCID sign-up makes "authenticated" a low bar. `queue_email` resolves recipients server-side from scholar ids (skipping anyone without a verified contact email, which is what enforces "never notify an unverified address") or, for `ProposalCreatedEditors`, from the proposal's own editor list. It accepts **no message body at all**.
2. **Consumer — `resend` function.** [supabase/functions/resend/](supabase/functions/resend/) posts to the Resend API, wrapping the body in the shared branded HTML shell ([supabase/functions/\_shared/emailShell.ts](supabase/functions/_shared/emailShell.ts)) and sending both an HTML and a text/plain alternative. In local dev (when `PUBLIC_SUPABASE_URL` points at 127.0.0.1) it logs to the console instead. **It requires the caller to present one of the project's secret keys** ([\_shared/auth.ts](supabase/functions/_shared/auth.ts)) — see Edge function authorization below. The `remind` function carries the same guard.
3. **Recipients are a list, not a name.** `emails` carries `cc text[]` and `reply_to text` alongside `email`, so a notice meant to be _one shared thread_ is one row and one send — the first recipient addressed, the rest copied — rather than N messages that never converge. Both are more recipient surface than `to`, so the open-relay rule tightens rather than loosens around them: neither may ever be written from a value that crossed the API. `queue_email` and `queue_steward_email` take no parameter for either, and the only writer is `_notify_new_volunteer`, which resolves every address from `scholars.email`. `cc` is null rather than empty when there is nobody to copy (a `CHECK` enforces it), because Resend treats `cc: []` as a malformed field and rejects the whole send — a rejection `pg_net` swallows, so the mail would vanish rather than fail.

   Two things key on addresses rather than ids and so had to learn about these columns: `forget_scholar` scrubbed `where scholar = … or sender = …`, which matches neither, so an erased address would have survived in mail about other people; and `export_scholar_data` reported only mail addressed to a scholar, omitting notices they were copied on. Both now resolve the address first — in erasure's case _before_ `scholars.email` is nulled, which is the only reason it is still reachable.

4. **Rendering happens at send time, not at the call site.** Rows carry `event` + `args`; the `resend` function renders them from the registry, which now lives at [supabase/functions/\_shared/templates.ts](supabase/functions/_shared/templates.ts) (re-exported from `src/email/templates.ts` for app code) so both runtimes share one source of truth. `subject`/`message` are nullable and null for such rows — `event` + `args` is a complete, re-renderable record. A caller can choose the template and its argument _values_ but cannot author prose, and `renderEmail` defangs URL schemes in argument values (`https://x` → `https[:]//x`) so a supplied value cannot become a clickable link inside branded mail. Templates opt specific positions out via `urlArgs` when the link is server-generated — only `VerifyEmail` does, which is why `queue_email` refuses to queue it.
5. **Reminder cron — `remind` function.** [supabase/functions/remind/](supabase/functions/remind/) is invoked daily at 22:00 UTC by a `pg_cron` job (`remind-daily`) defined in `supabase/migrations/`. It emails scholars with stale availability (fixed 90-day staleness, 30-day dedupe), and runs four venue-scoped reminder families in `getVenueReminders`, all sharing one cadence gate — `venues.transaction_reminder_frequency_days`, stamped to `venues.transaction_reminder_time`, stamped for every due venue including those with nothing outstanding so the frequency is honored rather than re-checked daily. It builds plain-text bodies, wraps them in the same shared shell, and posts directly to Resend. It is the only producer that runs outside the SvelteKit process.

   The four families are: proposed **venue-sourced** transactions → admins + minters; proposed **scholar-sourced** charges → the charged scholar (a co-author's unpaid share; the earlier code skipped these with `if (!transaction.from_venue) continue`, so the one person who could pay was the one person never asked again); **requested compensation** → the approver union; and **submissions ready to mark done** → their priority-0 editors.

   Two of those deserve their rules stated, because both are about _not_ sending mail. Compensation reminders key on `assignments.compensation_requested_at` rather than on `approved and not completed`: the latter describes a review still in progress just as well as it describes finished work, and a reminder that fires on both is one approvers learn to delete. Ready-to-mark-done reproduces `mark_submission_done`'s own blocker rule — every approved non-editor assignment compensated, at least one of them actually compensated, and an uncompleted priority-0 assignment to notify — so the reminder cannot suggest an action the RPC would refuse. The approver union is the same three branches as `can_approve_assignment` (venue admins, the submission's priority-0 assignees, holders of the role's approver), computed in TypeScript here because the function reads with `service_role` and so gets no help from the policies.

6. **Server-side fan-out — thank-you notes.** Author thank-you notes to reviewers (#22; the `thanks` table, vetting toggled by `venues.vet_thanks`) need privileged recipient resolution: the author may not see who reviewed their submission. The note bodies are still rendered from the `Emails` registry in `templates.ts` like every other email (`ThanksPendingReview` / `ThanksReceived` / `ThanksDeclined`), but the fan-out goes through the `queue_thanks_emails` RPC (`SECURITY DEFINER`) instead of `emailScholars`. The CRUD layer renders the copy and passes it in; the RPC resolves the audience (the submission's approved assignees / the venue's vetters / the author) and inserts rows into `emails` with `sender = null` so a recipient can't read the author's id off the email row. Its per-audience authorization is also what stops an author from bypassing vetting to message reviewers directly. The `resend` consumer brands and delivers these rows like any other.

**Links point at the sending environment.** Templates carry an `{origin}` token rather than a hardcoded host. `send_email()` reads the `site_url` vault secret — the same one that builds the verification link — and passes it in the POST body; `resend` resolves the token at render time and gives it to the branded shell for the wordmark link. The `remind` cron never touches the `emails` table, so it calls `site_origin()` (`SECURITY DEFINER`, granted to `service_role` alone) for the same value. Everything falls back to `https://reciprocal.reviews`, so a project that never configures the secret is unchanged.

Venue links are the one deliberate exception to send-time rendering. A template owns the path in its prose (`{origin}/venue/$4/submission/$5`) and takes only the segment as an argument, and that segment is resolved to the venue's web address **at queue time** by the producer — `venuePath`/`venuePathOf` in [SupabaseCRUD](src/lib/data/SupabaseCRUD.svelte.ts), `coalesce(v.slug, v.id::text)` in `public._notify_new_volunteer`, and a lookup map in the [remind](supabase/functions/remind/index.ts) cron, which builds its links itself. Queueing and sending are seconds apart (the `emails` AFTER INSERT trigger), so a rename cannot realistically overtake a message in flight; and if one did, the link still resolves, because the address it was renamed from is gone either way and the id form would have been no better.

The origin is resolved **in the template text, not through the argument path**, and that ordering is load-bearing twice over. Arguments have their URL schemes defanged unless the template declares the position trusted, so an origin arriving as an argument would render as `https[:]//…` and every link would be dead — which is exactly what was happening to `TransactionDeclined` and `TransactionDeclinedVenue`, whose whole link _is_ an argument; both now declare it via `urlArgs`. And the substitution happens before arguments are interpolated, so an argument value that happens to contain the literal `{origin}` stays literal.

**Optional notices.** A template may carry `optional: true`, which marks it a courtesy a scholar can silence; everything else is consequential — a charge, a decline, a verification, an assignment — and is always delivered. The registry is therefore the single source of truth for what can be turned off: `public.notification_settings (scholar, event, enabled)` holds the keys, the producer of an optional email checks that table before queuing, and the controls on a scholar's profile are generated from the marked templates, so a unit test asserts every marked template has a label. Preferences live in their own table rather than on `scholars` for two reasons: scholar metadata is world-readable, so a column there would publish everyone's mute list; and a nullable `venue` column added later gives per-venue muting without a rewrite, which no column can express. Absence of a row is the default, and the default is on. There is deliberately **no** column write boundary on that table, unlike `scholars` and `volunteers` — every column is part of "which of my own preferences this is", the row policy pins the only thing that matters, and revoking `scholar`/`event` would break PostgREST's upsert, which compiles to `on conflict do update set` over every column in the payload and is privilege-checked at plan time.

To add a new email: add a key to the `Emails` map in `templates.ts`, then send it — from application code via `emailScholars(...)`, or (when recipients must be resolved with elevated privileges, as for thank-you notes) via a `SECURITY DEFINER` fan-out RPC. There is deliberately no path that accepts a free-text address or a caller-authored body; if a new email needs recipients that aren't scholar ids, resolve them inside the RPC from a row the caller already had permission to write.

**Residual, deliberately deferred:** `queue_email` does not yet verify that the caller has a _relationship_ to each recipient, so a scholar can send a real template to a scholar they have no business emailing. That is bounded — no arbitrary prose, no external addresses, no attacker-supplied links — and attributable via `emails.sender`. Per-event authorization is a follow-up.

### Edge function authorization

Both functions are called only by the database — `resend` from the `send_on_email_insert` trigger, `remind` from the `remind-daily` cron — and both refuse callers that do not present one of the project's **secret** keys.

The check is deliberately a direct key comparison rather than a JWT claims check. Supabase's newer API keys (`sb_publishable_...` / `sb_secret_...`) are **opaque strings, not JWTs**, so there is no `role` claim to inspect; a claims-based check breaks the moment a project migrates key formats. Comparing the presented key against the keys the runtime injects works for both the legacy `service_role` JWT and the new secret keys, which is what lets the two formats coexist during a migration.

Three consequences worth knowing before touching this code:

- **`verify_jwt` is off** for both functions ([config.toml](supabase/config.toml)). The platform gate only understands JWT-shaped credentials and rejects the new API keys outright. That makes the handler check the _only_ gate, so it fails closed: if no secret key is present in the environment, every request is refused. It is also strictly narrower than `verify_jwt` ever was, since `verify_jwt` accepted any valid project JWT — including the public anon key.
- **The key travels on the `apikey` header**, not `Authorization: Bearer`, which is reserved for JWTs and rejects a new-format key as malformed. `send_email()` and the cron job both send it that way; the handler accepts either header so legacy callers keep working.
- **Local development needs `EDGE_SECRET_KEY`** in `.env`. Hosted runtimes inject `SUPABASE_SECRET_KEYS` and `SUPABASE_SERVICE_ROLE_KEY` automatically, but the CLI refuses to pass any `--env-file` entry beginning with `SUPABASE_`, so the local name cannot match the hosted one. The same variable seeds the `secret_key` vault entry, which is what keeps the local database and the local functions agreeing on one value.

**Edge functions are deployed by CI** ([staging.yml](.github/workflows/staging.yml), [production.yml](.github/workflows/production.yml)) alongside `supabase db push`. They were previously deploy-by-hand, which let a migration land against a stale function — a failure mode that is invisible, because `pg_net` swallows the resulting error and mail simply stops arriving.

### Addresses

[supabase/functions/\_shared/emailShell.ts](supabase/functions/_shared/emailShell.ts) owns both addresses, and re-exports them to app code through [src/email/emailShell.ts](src/email/emailShell.ts) so the Deno and SvelteKit sides cannot drift apart:

- **`FROM_EMAIL`** is `Reciprocal Reviews <notifications@reciprocal.reviews>`. The display name matters; without it clients render a bare address, which reads as no-reply automation.
- **`SUPPORT_EMAIL`** is `stewards@reciprocal.reviews`, set as `Reply-To` on every send from both the `resend` and `remind` functions, named in the shared footer, and surfaced in the interface by [src/lib/community.ts](src/lib/community.ts), which re-exports it rather than restating it, on `/contact`.

It is a Google Group in collaborative-inbox mode, not a mailbox: mail reaches every steward's own inbox _and_ creates one thread they can assign and resolve. Its MX and SPF records live at the domain root, while Resend's live on the `send.` subdomain, so the two do not collide.

### Steward notifications

`ProposalCreatedStewards` and `ReconciliationFailed` go to `SUPPORT_EMAIL` via **`queue_steward_email(_event, _args)`** ([20260823000000_steward_inbox.sql](supabase/migrations/20260823000000_steward_inbox.sql)), with the address defined once in SQL by `steward_inbox()`.

It is a separate function from `queue_email` rather than another branch inside it, because it gives up that function's central safety property. `queue_email` is safe because it never accepts a recipient: it resolves scholars by id and skips any without a verified contact email. `queue_steward_email` does not accept a recipient either, but it does write to an address that belongs to no scholar and was never verified through that path. **The event whitelist is what replaces the missing check:** the function refuses any event outside the steward-notification set, so it cannot become a general channel into the mailbox least able to ignore what arrives. Its residual exposure has the same shape as `queue_email`'s: an authenticated caller chooses argument values but no prose and no links, and `emails.sender` records who did it.

This replaced a per-steward fan-out, for two reasons. The visible one is collaboration, since N private copies gave no steward any way to see whether another had already picked a proposal up. The more serious one is that the fan-out selected `where steward = true and email is not null`, so `reconcile_ledger()`'s failure notification, the mail that says the token ledger is corrupt, could reach **nobody at all** if no steward had verified a contact address. A monitoring check whose delivery is conditional on unrelated profile state is the failure mode monitoring exists to prevent. The alias always resolves.

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

**Who may EXECUTE a `SECURITY DEFINER` function is its own access-control surface, and `revoke ... from public` does not close it.** Supabase's default privileges grant `anon`, `authenticated` and `service_role` EXECUTE on every function created in `public` _before_ a migration's revoke runs, and revoking from `PUBLIC` does not remove an explicit per-role grant. So a function whose file reads

```sql
revoke execute on function public._move_tokens (...) from public;
```

with no grant after it looks owner-only and is in fact callable by anyone at `POST /rest/v1/rpc/_move_tokens` with the publishable key. This is the same trap already documented twice here for **tables** — `token_events` ("Explicitly revoked, not merely un-granted") and the `tokens` grants — appearing a third time for **functions**, where nobody had looked until #109. `public._notify_new_volunteer` is the one that got it right, revoking `from public, anon, authenticated`; its neighbours copied the comment without the third line.

It mattered. `public._move_tokens` and `public._welcome_volunteer` are `SECURITY DEFINER` and perform **no authorization of their own** — by design, because they are steps of an RPC that has already authorized the caller. Both were anon-executable. Demonstrated on a local stack before the fix: a single anonymous POST to `_move_tokens` emptied a venue's 50-token reserve and minted 950 more into a scholar's balance, with no session at all. `tokens_as_of` and `reconcile_ledger` leaked reads that RLS elsewhere deliberately closes.

Every definer function's audience is therefore set in one place, [20260831000000](supabase/migrations/20260831000000_definer_function_grants.sql), by category:

| Category                                                                            | Audience                 |                                                                   |
| ----------------------------------------------------------------------------------- | ------------------------ | ----------------------------------------------------------------- |
| Internal helpers (`_`-prefixed)                                                     | owner + `service_role`   | steps of an authorized RPC, never entry points                    |
| Trigger functions                                                                   | owner + `service_role`   | invoked by the trigger, never called directly                     |
| Operational (`reconcile_ledger`, `tokens_as_of`, `replay_audit_log`, `site_origin`) | `service_role`           | run by crons and recovery                                         |
| Ordinary RPCs                                                                       | `authenticated`          | each re-implements its own authorization                          |
| `verify_email`, `currency_holder_counts`                                            | `anon` + `authenticated` | followed from an email before sign-in; aggregate supply is public |
| **Policy predicates**                                                               | `anon` + `authenticated` | **load-bearing — see below**                                      |

The policy predicates stay open on purpose. A policy expression is evaluated as the **querying** role, so that role needs EXECUTE on every function the policy calls, and the `submissions` SELECT policy is granted to `{anon, authenticated}` and calls `isAdmin`, `isPriorityZero` and `isRoleApproverVolunteer`. Revoking those from `anon` breaks anonymous submission viewing outright. They are safe to leave open because each is a read-only predicate about the _caller's_ own relationships (`auth.uid()`, null for anon) over inputs that are publicly readable anyway.

**`supabase db diff` does not compare function ACLs**, so the drift check that guards the rest of this schema is blind here. [supabase/tests/rls/definer_grants.sql](supabase/tests/rls/definer_grants.sql) is the only guard rail: it fails if any definer function outside an explicit allowlist becomes anon-executable, and if any `_`-prefixed helper becomes reachable at all. A new definer function must be added to the migration's lists, and to that allowlist if it is meant to be callable without a session.

### Balance privacy

Balances are private ([#109](https://github.com/reciprocalreviews/reciprocalapp/issues/109), DESIGN.md). The rule is split across two layers for a reason worth keeping:

- The **`tokens` SELECT policy** answers only what a per-row test must — `scholar = auth.uid() or venue is not null`. Two column comparisons, no subqueries, no function calls. A policy is evaluated once per row and this table holds one row per token, so a reserve carrying a community's supply pays for it a quarter of a million times; anything cleverer here would undo the indexing work of `20260830000000`.
- The **audience rule** — minters, venue admins, and accepted active volunteers at a venue on that currency — lives in `public.can_see_balances(currency)` and is asked **once per call** by `public.scholar_balances`, which is `SECURITY DEFINER` and so must carry it. That is what lets the audience be as broad as it is at no per-row cost.

`scholar_balances` filters rather than raising: a caller outside the audience still gets their own row, so a reviewer's submission page does not error merely because they may not see their peers'. The submission page hides the balance column for non-approvers **and** neutralizes `getBalance`, because `sortAssignees`/`sortBids` order ascending by balance — leaving the column out but the ordering in would keep the row order as a balance oracle.

**A predicate helper used in a policy must be declared `STABLE`.** `isAdmin`, `isSteward`, `isMinter`, `isPriorityZero`, `isAssigned`, `isAuthor`, `isConflicted`, `isInApproverChain`, `isRoleApproverVolunteer`, `can_approve_assignment` and `can_claim_editor_role` were all declared `LANGUAGE sql SECURITY DEFINER` with no volatility marker — which means `VOLATILE`, the default. Postgres will not hoist, cache or fold a `VOLATILE` function, so each was re-executed **for every row** the policy was checked against, and several run a query of their own to answer (`isPriorityZero` joins two tables). `isSteward()` shows the cost most plainly because it takes no arguments at all and so has nothing to vary on: as `VOLATILE` the planner still called it once per row — ~57ms over 20,000 rows, against 0.4ms once it is hoisted to a single call. All eleven were marked `STABLE` in [20260830020000](supabase/migrations/20260830020000_stable_rls_helpers.sql); `submission_has_editor` and `venue_submission_editors` already were, so this is the rest of the family catching up rather than a new claim. Nothing about their behaviour changes: `STABLE` promises only that a function returns the same answer for the same arguments within one statement, which is what a policy predicate must already do to be coherent.

A known cost that this does **not** fix: the `transactions` SELECT policy's minter and venue-admin branches are correlated subqueries against the `currencies.minters` and `venues.admins` **array columns**, keyed on the row's own columns, so they cannot be hoisted and are evaluated per row — `EXPLAIN` on a venue admin's transaction list shows the subplans looping once per candidate row, and the six-way `OR` defeats the partial indexes besides. The root cause is the array columns themselves; making those branches indexable means normalizing `admins`/`minters` into join tables, which touches authorization everywhere and is its own piece of work. In the meantime the paginated lists ask for `{ count: 'exact' }` on the **first page only** — the total is displayed and drives the "load more" stop condition, so it must stay exact, but it was being recomputed on every page, making each "load more" pay for the page twice.

### Submission completion

Submission completion is a guarded action implemented by the `mark_submission_done(submission_id, payment_template, mint_template)` RPC ([supabase/migrations/20260517000000_mark_submission_done.sql](supabase/migrations/20260517000000_mark_submission_done.sql)). It authorizes only priority-0 editors of the submission, validates that every approved non-editor assignment is already completed, and — in one atomic action — compensates every uncompleted priority-0 assignment, flips `submissions.status` to `done`, and stamps `submissions.completed_at`. If the venue cannot cover the total editor payout, it records a single proposed mint sized to the shortfall and returns without changing status; if there are pending non-editor assignments, it returns the blocker list without changing anything.

To enforce this gate, the table-level UPDATE grant is removed from the `authenticated` role and re-granted only on the editable columns — omitting `status` and `completed_at`. (A column-level `REVOKE` alone is a no-op while a table-wide `GRANT ALL` confers UPDATE on every column, so the grant must be narrowed, not merely revoked.) The RPC is `SECURITY DEFINER`, so it is the only path that can write these columns. The result: **done is terminal** — once set there is no API path to revert it, by design.

The same narrowing now also denies DELETE on `venues`, `currencies`, and `submissions` — policy plus a table-level `revoke delete`, matching the `tokens` treatment. Each previously granted deletion to stewards/admins/minters, and each was unreachable: no UI calls them and `CRUD` declares no method for them, so the only way to exercise one was a hand-written PostgREST request. What they permitted was not small. Deleting a venue cascades through its roles to every volunteer, assignment, and compensation row, plus preference levels and thanks; only the money tables' plain (non-cascading) foreign keys stood in the way, which is protection by accident rather than by design. `service_role` keeps its grant, so recovery work at a psql prompt is unaffected.

`volunteers` received the same treatment, and there the dormant path was not merely untidy. A volunteer row is what stops a venue's welcome grant being made twice: `create_volunteer` and `accept_role_invite` size the grant by counting the scholar's existing rows at the role's venue, and `volunteers.active` exists so that unvolunteering keeps the record. DELETE was granted to venue admins and the volunteering scholar and called by nothing — no UI, no `CRUD` method, no RPC — so deleting your own row and volunteering again minted the welcome amount a second time. UPDATE was open the same way for a different reason: the policy authorized the row and said nothing about columns, and its `USING` expression named `scholarid` but never `roleid`, so a scholar could repoint their row to a role at another venue and reset the count without deleting anything. (Reassigning it to another `scholarid` was already refused — Postgres applies a policy's `USING` expression as its `WITH CHECK` when none is given.) The table UPDATE is now revoked and re-granted on `active`, `expertise`, and `papers` only; `accepted` is left out because `accept_role_invite` is what settles the grant, and it is `SECURITY DEFINER`, so the revoke does not reach it.

The same pattern makes `transactions` an immutable record, on both sides of a row's life. The table-level UPDATE is revoked and re-granted only on `status`, `tokens`, and the decline fields, locking the identity columns. INSERT is narrowed the same way — re-granted only on the columns a caller may legitimately supply, omitting `id`, `created_at`, and `seq` — so a client can propose a transaction but cannot choose its identity, backdate it, or pick its place in the order. DELETE is denied outright: the policy named `"transactions cannot be deleted"` previously had a `USING` clause that in fact _granted_ deletion to any minter of the currency, so a minter could erase approved transfer history while the tokens those rows described stayed put, leaving tokens with no account of how they got where they are.

Column grants cannot express a rule that depends on the row's _current_ state, and two such rules matter, so a `BEFORE UPDATE` trigger carries them ([20260808030000](supabase/migrations/20260808030000_transactions_immutable.sql), error code `RR005`):

- **A decision is final.** `status`, `tokens`, `decliner` and `decline_reason` are writable because a proposed transaction has to become approved or declined — and nothing stopped that happening twice. An approved transfer, tokens already moved and recorded in `token_events`, could be flipped to `declined` afterwards, leaving the ledger saying value moved and the transaction saying it was refused.
- **The amount cannot be resized.** There is no amount column; the amount _is_ `cardinality(tokens)`. Since `tokens` is writable, the amount was writable: a proposed row carrying N placeholders could be approved with a different number of real ids. Every legitimate path already preserved the count — `approve_transaction` sizes its work from `cardinality(_txn.tokens)` — so this makes a habit into a rule. Filling placeholders in at the same count remains allowed, since that is what approval is.

A trigger rather than a policy or a grant, because those decide by _who_ is asking while this decides by what the row already is, and it must bind the `SECURITY DEFINER` RPCs and anyone at a psql prompt equally. A restore is unaffected: data loads under `session_replication_role = replica`, so historical rows are not judged against rules they predate.

`seq` is a `bigint` from a sequence, and it is what makes the order of history well-defined. `created_at` defaults to `now()`, which is transaction _start_ time, so every row a single RPC writes carries an identical timestamp — `create_submission` inserts one charge per author that way. Sorting on `created_at` alone therefore leaves ties the planner may break differently per query, and a `LIMIT`/`OFFSET` over an unstable sort can return one row on two pages while skipping another; the three paginated transaction lists all sort `created_at desc, seq desc` for this reason. Note that a sequence gives _insertion_ order rather than _commit_ order, so anything treating `seq` as a replication watermark should compare against `pg_snapshot_xmin(pg_current_snapshot())` instead of assuming `max(seq)` is final.

Per-editor compensation amounts come from `compensation(role, submission_type)`; multi-editor submissions are supported and all priority-0 editor assignments are paid in the same transaction. The RPC returns a structured JSONB result (`completed | blocked | insufficient`) that the application layer narrows with a runtime type guard before dispatching `WorkCompensated` emails (per-recipient, surfaced as notification banners via the `handle()` feedback channel).

### Two rules that look like one: approving an assignment

There are two distinct authorization questions here, and they were easy to confuse because one of them used to be named as if it were the other.

- **`can_approve_assignment(submission, role)`** ([20260816010000](supabase/migrations/20260816010000_can_approve_assignment.sql)) is the approval rule: a venue admin, or the holder of an **approved assignment on this submission** for either the venue's priority-0 role or the role that approves the one in question. `complete_assignment` calls it, so the enforcing copy exists once. [src/lib/data/canApproveAssignment.ts](src/lib/data/canApproveAssignment.ts) is the UI-gating mirror; the two are pinned to the same table of cases by [canApproveAssignment.unit.ts](src/lib/data/canApproveAssignment.unit.ts) and by the `create_submission`/`complete_assignment` cases in [atomic_crud_rpc.sql](supabase/tests/rpc/atomic_crud_rpc.sql).
- **`isRoleApproverVolunteer(role)`** (formerly `isApprover`) asks something else entirely: is the caller an **accepted volunteer** on the role that approves this one, anywhere in the venue? It reads `volunteers`, takes no submission, and has no admin or priority-0 branch. It is the `USING` clause of the assignments UPDATE policy, where an AE must be able to approve a bid on a submission they hold no assignment on.

Both of those, along with `isPriorityZero`, `mark_submission_done` and the submissions author-list lock, key on **priority 0**. `roles.priority` therefore carries authority, not just presentation, and the invariant that makes it meaningful is that a venue has exactly one role at priority 0. Nothing used to establish that invariant: the column defaults to `0` and roles were created with a plain insert, so every role a venue admin added arrived at priority 0 and silently made its accepted volunteers editors — visible in the UI only as several role cards each claiming to be the venue's highest priority. **`create_role(venue, name, description)`** ([20260828030000](supabase/migrations/20260828030000_role_priority.sql)) is what establishes it: it takes an advisory lock on the venue and inserts at `max(priority) + 1`, so a venue's first role — the Editor that proposal approval creates — still lands at 0 and every later one goes to the bottom. Unusually among the RPCs here it is `security invoker` rather than `security definer`, precisely because it needs no authorization logic of its own: the existing "only admins can create venue roles" policy applies to the insert unchanged, which [create_role_rpc.sql](supabase/tests/rpc/create_role_rpc.sql) asserts by checking that a non-admin caller still gets 42501. The same migration renumbers venues that already had ties. Reordering remains the admin-facing way to move that authority, via the ↑/↓ controls that renumber the venue densely.

They disagree in both directions — an accepted approver with no assignment satisfies the second and not the first; a venue admin satisfies the first and not the second — so unifying them is a permissions change, not a refactor. Narrowing `isRoleApproverVolunteer` to match the approval rule would silently revoke UPDATE from every AE approving a bid, breaking bidding. It therefore keeps its behaviour and loses its misleading name. A third near-copy, in `SupabaseCRUD.requestCompensation`, picked email recipients by a rule that omitted the priority-0 editor branch and treated admins as a fallback rather than a first-class branch, so the two people most able to act on a compensation request were often the two who never heard about it; it now uses the same three-branch union.

### Resubmission links and per-type cost

A submission records its predecessor two ways: `submissions.previous` is an internal foreign key (`on delete set null`) to another submission, preferred wherever the chain is displayed; `submissions.previousid` is the legacy free-text external manuscript ID, retained for predecessors not on the platform (and matched against `externalid` within the same venue only as a fallback). Individual submissions set `previous` from a dropdown of the author's own prior submissions in the venue — choosing one mirrors its external ID into the (then read-only) `previousid` field **and auto-selects the matching revision submission type** (the `submission_types` row whose `revision_of` points at the predecessor's type). A typed external ID that matches one of the author's priors does the same best-effort. `bulk_import_submissions` best-effort resolves each row's `previousid` to an on-platform `previous` (exact `externalid` match within the venue).

Submission cost is **per submission type**: `submission_types.submission_cost` (`not null default 0`); there is no venue-wide submission cost. Each type is a different amount of work, so a resubmission — being its own revision type — simply carries its own cost; no separate resubmission cost exists. Admins edit a type's cost in the submission types table on the venue dashboard. The new-submission form charges the selected type's cost, and the bulk-import RPC sizes the mint by summing each row's submission type cost.

`create_submission` enforces that the author charges add up to that cost (`RR007`) and that no author is listed twice (`RR008`) ([20260816000000](supabase/migrations/20260816000000_submission_cost_and_authors.sql)). Both rules previously lived only in the new-submission form, so they held for callers who came through the form and for no one else — anything reaching the RPC directly could name its own price, and a duplicated author was charged twice for one manuscript because the RPC's loop indexes the authors array positionally. Neither can be a `CHECK` constraint: the cost rule spans two tables, and the duplicate rule must not apply to bulk-imported submissions, which arrive by a different path with no payments. The same call also verifies that the submission type belongs to the venue being submitted to, which was never checked. `src/lib/data/charges.ts` is the client half, so the form can refuse before the round trip rather than instead of it.

`RR009` completes the set ([20260817010000](supabase/migrations/20260817010000_create_submission_author_check.sql)): the caller must be one of `_authors`, or an admin of the venue (which is how DESIGN's "submissions can be added manually by editors" works). The RPC previously required only that _someone_ was signed in, and self-service ORCID sign-up makes that a low bar — so any account could create a submission at any venue and leave proposed charges sitting against scholars who had never heard of it, each of which the charged scholar then sees on their dashboard and now receives mail about. The form's `isNonAuthor` guard remains, but it was never a control: it only evaluates once an ORCID lookup has resolved, and nothing obliges a caller to use the form.

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

### Substitution, and why inputs are escaped

Every string passes through [interpolate.ts](src/lib/locales/interpolate.ts) — the one choke point — which makes two replacements in order: `$name` from the locale's own `shorthand` table, then `{name}` from the caller's `inputs`. An unrecognized key is left literally as `$name` or `{name}`, so a missing string shows up as a visible placeholder rather than a hole in a sentence.

`<Text markdown>` renders its result through `marked` and `{@html}`, and `marked` passes raw HTML through untouched. That makes an input _markup_, not text — and several inputs are authored by users: `venue.description`, `proposal.title`, `proposal.url`. Before this was addressed, a venue description of `<img src=x onerror=…>` executed for every visitor to that venue.

So **inputs are escaped by default in the markdown path**. A value that genuinely is markup the platform generated must say so by arriving as `Html` from [html.ts](src/lib/locales/html.ts):

```svelte
<Text
	markdown
	path={(l) => l.page.home.call}
	inputs={{ cost: tokenChip(locale().widget.tokens, 10) }}
/>
```

`html()` is the only way to opt out, which makes every exemption one `grep` away. Three details are load-bearing:

- **Shorthand is not escaped.** It is authored in the locale file beside the strings that use it, and `$delete` is `✖`.
- **Escaping is skipped in the plain-text path**, where Svelte escapes the interpolated result itself. Doing both would double-encode and show the reader a literal `&lt;`.
- **Both passes use function replacers**, so a `$1` or `$&` in a substituted value is inserted literally, and a `{name}` inside one is never re-scanned.

The current holder of an `html()` exemption is [tokenChip.ts](src/lib/components/tokenChip.ts), which renders the review-token chip as a string so it can sit inside a localized sentence — something `<Text>` cannot do with a component. It duplicates `Tokens.svelte`'s markup deliberately; the two share class names defined once in the global block in `app.html`, because Svelte's scoped styles never reach `{@html}` content. **Change one and change the other.**

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

- Localized routes live under `src/routes/[[lang]]/`. `[[lang]]` is an optional locale prefix that defaults to `en`.
- A few routes sit at the root instead, because their URLs must be stable and locale-free: the landing page (`+page.svelte`), `/auth/callback` (the ORCID redirect target, which is in a provider allow-list), and `/sitemap.xml`.
- Dynamic segments use the project's domain identifiers: `[id]` (scholars, currencies), `[venueid]`, `[submissionid]`, `[proposalid]`.
- **`[venueid]` is not a uuid.** It is the venue's web address (`venues.slug`) once it has chosen one, and its id until then. Both are resolved in one place — [venue/[venueid]/+layout.ts](src/routes/[[lang]]/venue/[venueid]/+layout.ts) via `getVenueByPath`, which picks a column by looking at the segment; `venues_slug_check` forbids an address shaped like a uuid precisely so that stays a decision rather than a guess. The layout then **307-redirects** the id form to the address (307, not 308: a permanent redirect is cached indefinitely, and this target stops existing the moment somebody renames the venue). So every child load must take `venue.id` from `parent()` and never key a query on `params.venueid` — the columns those queries filter on are uuids, and an address reaches them as a `22P02`. The same applies to the realtime filters in the venue layout, which would otherwise silently subscribe to nothing. `NO_VENUE_ID` in [venuePath.ts](src/lib/data/venuePath.ts) is what child loads use when nothing resolved.
- Route directories may contain `+page.svelte`, `+page.ts`, `+layout.svelte`, `+layout.ts`, plus arbitrary co-located helper Svelte files (e.g. `Roles.svelte`, `NewSubmission.svelte`) when a page is too big for one file.

## UI components

[src/lib/components/](src/lib/components/) is the shared design system: `Button`, `Card`, `Cards`, `Form`, `TextField`, `Slider`, `Tag`, `Tags`, `Page`, `Nav`, `Footer`, `Feedback`, `Loading`, `Dialog`, and so on. New UI should compose these rather than introducing one-off styling. One of them is not generic: `Logo` draws the brand mark with `currentColor`, and its path data is duplicated in [static/brand/logo.svg](static/brand/logo.svg) for the copies that leave the app — change the geometry in both. Components accept locale-path functions where they take user-visible text.

## Build and release

- `npm run build` runs [scripts/maybe-updates.js](scripts/maybe-updates.js) first, which invokes `npm run updates` only when `$CI` is set. CI builds regenerate `src/routes/[[lang]]/updates/updates.json` from [CHANGELOG.md](CHANGELOG.md) via [scripts/updates.js](scripts/updates.js); local builds reuse whatever was last committed, so the file doesn't churn on every dev rebuild. Run `npm run updates` manually if you want to regenerate it locally.
- `npm run icons` rasterizes [static/brand/logo.svg](static/brand/logo.svg) into the PNGs that SVG cannot cover — the apple-touch icon (iOS ignores SVG), the favicon fallback, and the 1200×630 social card (link scrapers reject SVG). It drives Playwright's Chromium, which is the only rasterizer in the repo, and is **deliberately not part of `npm run build`**: builds run on Vercel, which has no browser installed. Run it by hand and commit the output.
- `npm run deploy` ([scripts/deploy.js](scripts/deploy.js)) fast-forwards `main` to `dev` and pushes it. The push triggers CI; CI does the actual deploy. The merge is `--ff-only` and the script refuses to run when `main` holds a commit `dev` does not, when `dev` is unpushed, or when the tree is dirty — a plain `git merge` would otherwise reconcile two diverged branches inside the commit that deploys them, sending production a tree no CI run and no staging deploy had ever seen. That is what #148–#150 set up by landing on `main` directly, and it is the failure this guard exists for.
- `package.json#version` is bumped manually as part of changelog updates.

### Branches

Work flows one way: feature branch → `dev` → `main`. `dev` is the **repository default branch**, which is what makes that the path of least resistance — a fork starts on `dev`, and a new pull request proposes `dev` as its base without anyone choosing it. `main` is the deploy target and moves only by fast-forward from `dev`.

The arrangement rests on one invariant: **`main` never holds a commit `dev` does not.** While it holds, what production receives is byte-identical to what staging ran. It was broken once, when three pull requests were opened against `main` back when `main` was the default, and the branches then carried a week of independent work each — the reconciliation, when it finally happened, conflicted in ten files across both deployed feature sets. Three things now defend it: the default branch, so mistargeting takes deliberate effort; the `base-is-dev` job in [pr-target.yml](.github/workflows/pr-target.yml), which fails a pull request that targets `main` from anywhere but `dev`; and `main-is-contained-by-dev` in the same workflow, which re-checks the invariant on every push to `main` and is silent unless it has already been broken. `npm run deploy` refuses rather than papering over it.

Two consequences worth knowing. Scheduled workflows run from the default branch, so the backups run from `dev` (see [Backups](#backups)). And the branch protection ruleset names `main` and `dev` explicitly rather than by `~DEFAULT_BRANCH`, so moving the default does not silently unprotect either.

### Deployment pipeline

Vercel's automatic git-deploys are **disabled** for `dev` and `main` (see [vercel.json](vercel.json)`#git.deploymentEnabled`). Deploys are driven by GitHub Actions instead, so a broken push never reaches hosting.

Each branch push triggers a workflow that runs jobs in this order:

```
[unit-tests, playwright, locale-validation, rls-tests, repo-checks]   ── parallel
              │
              ▼ (prod: all pass · staging: not gated)
           migrate         ── supabase db push · functions deploy
              │
              ▼
           vercel          ── vercel pull → build → deploy
```

`repo-checks` is [ci.yml](.github/workflows/ci.yml) — formatting, generated-type freshness, and `schemas/`-vs-`migrations/` drift — called by both deploy workflows. It triggers on `pull_request` on its own, but `dev` and `main` are pushed to directly, so on the deploy path it only runs because these workflows call it. Without that it never ran on a release at all, which is exactly where a stale `database.ts` or a drifted schema file would first matter.

Migrations are applied before the Vercel deploy so schema changes are in place before the code that depends on them goes live.

All four suites also run on **pull requests**, so the branch is the first place a regression shows rather than the deploy. Playwright was the last to join them, and the reason it held out is the reason it mattered: four runners, each with a Supabase stack and a browser, versus a minute for the others. What that thrift bought was a suite whose first execution of any change was the push that deploys it — after review, on `main`, at the moment it blocks a release. It did precisely that when a `$lib` import in the Playwright helper collected zero tests on every shard: no local run could have failed on it, because it only breaks where `.svelte-kit/` has never been generated, and a developer machine always has one. A check that runs only after merge cannot block the merge. On PRs the suite is superseded by concurrency when a branch is pushed again, and skipped on forks, which cannot read `TEST_ENV`.

Two steps run immediately before `supabase db push`, because a bad migration is the likeliest cause of data loss and the one moment you know is coming. The first records the append-only watermarks into the job summary, which makes "restore to just before the deploy" a precise instruction — wall-clock cannot express it when a deploy and user activity interleave. The second refuses to push when production carries migrations this repository does not, so a hand-applied change is reconciled rather than silently overwritten.

- `main` → [.github/workflows/production.yml](.github/workflows/production.yml) deploys to Vercel **production** against the production Supabase project. Here `migrate`/`vercel` **gate on the tests** — if any test fails, neither the migration nor the deploy runs.
- `dev` → [.github/workflows/staging.yml](.github/workflows/staging.yml) deploys to a Vercel **preview** environment against the staging Supabase project. Staging is a throwaway test target, so its deploy is **not gated** on the tests: they still run in parallel for signal, but a red e2e/unit/rls run won't block the preview (it keeps deploys fast and lets the slow e2e suite finish out-of-band). The gate is what keeps a broken change from reaching `main`/production.

Required GitHub secrets: `SUPABASE_ACCESS_TOKEN`, `STAGING_DB_PASSWORD`, `STAGING_PROJECT_ID`, `PRODUCTION_DB_PASSWORD`, `PRODUCTION_PROJECT_ID`, `TEST_ENV`, `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`. Per-environment runtime config (Supabase URL, anon key, Resend key, etc.) lives in Vercel's environment variable settings and is pulled at build time by `vercel pull`.

## Change history

Two append-only logs record what changed and why: [token_events](supabase/schemas/token_events.sql) for the token economy, and [audit_log](supabase/schemas/audit_log.sql) for everything else. They share their design — trigger-captured, foreign-key-free, append-only by trigger, invisible to the API, absent from realtime — and differ only in shape.

### token_events

An append-only record of every change of token ownership. It exists because neither of the two tables that look like they should provide one actually does.

`public.tokens` is the **state**: one row per token, and a transfer is an in-place `UPDATE` of its `scholar`/`venue` columns. It has no `created_at`, no history, no versioning — so once ownership is overwritten the previous owner is gone from the database entirely. Balances are `count(*)` over that table, which means the current balance is the only thing the schema knows.

`public.transactions` looks like the ledger and is not. Nothing derives from it and it derives from nothing: it has no amount column (the amount is `cardinality(tokens)`), its `tokens` array is rewritten from placeholder UUIDs to real ids on approval, and it records an _assertion_ about who paid rather than an _observation_ of what moved. It stays in step with reality only by convention inside the RPCs.

`token_events` is the observation. Four decisions shape it:

- **Capture is a trigger on `tokens`, not logging inside the RPCs.** A trigger sits below RLS and below the RPC boundary, so it catches every path — the RPCs, a direct PostgREST write, a `service_role` script, manual psql surgery during an incident, and a restore. Logging inside the RPCs would require believing every write goes through them, which is exactly the belief that proved false when `tokens` turned out to be directly writable from the browser. Completeness by construction is the point.
- **Attribution flows through the `app.txn` GUC.** Each RPC publishes the relevant transaction id immediately before touching `tokens` and clears it immediately after, so `select count(*) from token_events where op = 'move' and txn is null` is **zero in a healthy system**. Anything else is value that moved with no transaction explaining it. Clearing matters as much as setting: without it, an unattributed write later in the same database transaction would silently borrow the previous id and the alarm would read clean while being wrong.
- **No foreign keys**, deliberately. A log constrained by the rows it describes cannot outlive them, and `scholars.id` cascades from `auth.users` — so an accidental account deletion would delete the evidence of itself. FK-free is what lets the log survive a cascade and what lets a reconciler _detect_ one.
- **Append-only is enforced by a trigger, not RLS**, because `postgres` and `service_role` bypass policies and are exactly who would be at the keyboard during an incident. The single sanctioned mutation is erasure, which nulls `scholar`/`prev_scholar`/`actor` under an explicit `app.erasure` flag and leaves the movement intact, so balances stay reconstructible after a scholar exercises their right to be forgotten.

`tokens_as_of(timestamptz)` replays the log to reconstruct ownership at any past instant. Diffing it against `tokens` turns "we discovered on Thursday that Tuesday's deploy corrupted balances" into a targeted repair instead of a restore that discards two days of legitimate work. **Mind the clock**: `token_events.at` is `clock_timestamp()`, which advances during a transaction, while `now()` is transaction _start_ time — so `tokens_as_of(now())` called from inside the transaction that just wrote events silently omits them. The argument defaults to `clock_timestamp()` for that reason; pass an explicit timestamp only when you mean the past.

The table is **not** in the `supabase_realtime` publication — a 500-token mint would fan 500 rows out to every connected client, each firing `invalidateAll()` — and it is readable only by `service_role`. Historical token ownership is not exposed anywhere in the product, and would leak reviewing activity that venue anonymity settings exist to protect.

Behaviour is covered by [supabase/tests/invariants/token_events.sql](supabase/tests/invariants/token_events.sql), which asserts the properties the design rests on against real RPC calls: capture, attribution, that a deliberate out-of-band write shows up unattributed, that `tokens_as_of()` reproduces `tokens` exactly, and that each token's chain of previous owners is unbroken.

### audit_log

The general counterpart, covering the 15 mutable state tables plus `transactions`. Each row holds the whole `before` and `after` as `jsonb`, the acting scholar, and the transaction id that wrote it. Two things motivate it:

- **Forensics.** `venues.admins`, `currencies.minters`, and `scholars.steward` are privilege-bearing columns edited by read-modify-write on an array — lossy under concurrency and invisible afterward. Nothing else can say when someone gained admin on a venue, or who granted it. `transactions` is included for the same reason: the row records who _declined_ a transaction but never who approved it. `scholars.steward` now has that history, and gets it for free: `set_steward` needs no auditing code of its own, because `log_audit_event` records `auth.uid()` — the **caller**, since `SECURITY DEFINER` changes the current user but not the JWT claim. The pgTAP suite asserts the attribution explicitly, that being the most plausible way the feature could quietly lose its trail while still appearing to work.
- **Recovery point.** Without PITR, a nightly dump means up to 24h of loss. Replaying `after` in `seq` order lets a restore catch up from the dump instead, and ordering by `seq` respects foreign-key causality for free, because the original writes did.

Four tables are excluded deliberately: `tokens` (covered by `token_events` in a shape ~4× smaller, and it is the highest-volume table in the schema), `emails` (already immutable, and auditing it would store every rendered message body twice), `email_verifications` (holds a sha256 token hash — copying a credential-like value into a longer-lived table widens its exposure for nothing), and the two logs themselves.

Whole-row payloads rather than deltas, because replay is then an upsert rather than a merge, and correctness matters more than storage at this volume. **No-op updates are skipped** — the app calls `invalidateAll()` after every write and several components re-save unchanged values, which is the difference between a usable log and noise.

One consequence worth holding onto: because the payloads are whole rows, this table contains scholars' contact emails and the bodies of author thank-you notes, making it strictly more sensitive than any single table it records. `forget_scholar()` will have to scrub here as well as in `token_events` and `transactions`.

### reconcile_ledger

The logs make corruption _findable_; [reconcile_ledger()](supabase/migrations/20260808010000_reconcile_ledger.sql) makes it _found_. It records every run in `public.reconciliations`, and on failure raises a warning into the Postgres log and mails the steward inbox.

It runs on **two** schedules ([20260830030000](supabase/migrations/20260830030000_bounded_reconcile_ledger.sql)), because three of its checks scan the entire history of the token ledger and that history only grows: `replay_mismatches` does a `distinct on` over every `token_event` ever recorded, `chain_breaks` runs a window function over the same, and `dangling_token_refs` unnests every approved transaction's token array — one row per token ever moved. Left unbounded, the tool for detecting corruption is the tool that stops finishing once there is enough production to have corruption, and a cron job that times out fails silently: no row, no mail, no alarm.

So `reconcile_ledger(_since timestamptz)` bounds those three, and the nightly 22:15 run passes a 30-day window. That alone would leave a hole — the window keys on a token having _moved_ recently, and the corruption these checks look for is a write that escaped the logging trigger, which by definition leaves no event behind, so a token last touched a year ago and quietly altered today would never enter the window. The unbounded run therefore still happens, weekly at 03:45 Sunday. It is allowed to be slow; it is not allowed to be absent. `conservation_violations` is deliberately **not** bounded on either schedule: it compares current state against the transactions that produced it, so it is O(the economy) rather than O(its history), and it is the check that catches a lost or duplicated payment. Each run records its own `duration_ms`, so the trend is visible before it becomes an outage.

Six checks decide `ok`, and each answers a question nothing else in the schema can:

| Check                      | Catches                                                                                                                                                                       |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `unattributed_moves`       | Value that moved with no transaction explaining it — a bug, a careless migration, or someone moving balances by hand                                                          |
| `replay_mismatches`        | The ledger no longer reproduces `tokens`                                                                                                                                      |
| `chain_breaks`             | A write that escaped the trigger, or a partial restore. Invisible to a state comparison, because the end state can still look right                                           |
| `placeholders_in_approved` | An approved transaction still holding null-UUIDs: an amount recorded for a movement that never happened                                                                       |
| `dangling_token_refs`      | An approved transaction citing a token that is gone, or in another currency                                                                                                   |
| `conservation_violations`  | The two narratives disagreeing holder by holder — computed only when provenance is clean, since unexplained tokens would otherwise produce drift check 1 has already reported |

Two further signals are **advisory** and deliberately do not flip `ok`: `unattributed_mints` and `orphan_proposals`. Both are real signal in production and should be zero there, but [supabase/seed.sql](supabase/seed.sql) inserts tokens directly and ships one proposal with no supporters, so every development and CI database carries them permanently. Folding them into `ok` would make the check red everywhere and therefore ignored — which is the failure mode a monitoring check is most prone to.

Each check is covered by [supabase/tests/invariants/reconcile_ledger.sql](supabase/tests/invariants/reconcile_ledger.sql), which breaks the invariant deliberately and asserts the count moves. A checker that returns `ok` regardless is worse than none, because it actively reassures.

### Scheduled jobs

Two `pg_cron` jobs now run: `remind-daily` at 22:00 UTC and `reconcile-ledger` at 22:15, staggered so they never contend. Both live in `cron.job`, which is **cluster state outside every schema dump** — captured separately by [dump.sh](supabase/dr/dump.sh) into `cron.json` and by `quarantine.sql` before a restore. That is not theoretical: `remind-daily` was silently lost once by a `supabase db diff` run (see `supabase/migrations/20260517230819_restore_remind_cron.sql`).

## Data rights

The terms page has promised data portability and erasure since it was written; [20260808050000](supabase/migrations/20260808050000_erasure_and_export.sql) is the machinery behind them.

**Export** is `export_scholar_data()`, served as a download by [scholar/[id]/export/+server.ts](src/routes/[[lang]]/scholar/[id]/export/+server.ts). Authorization lives in the function rather than the route — `SECURITY DEFINER`, checking `auth.uid()` and letting a steward through for a request that arrives out of band — so a future CLI or support script cannot reach the data by going around the endpoint. The token history it includes is only possible because of `token_events`; before the ledger there was no record of where a scholar's tokens had been.

**Erasure is anonymisation in place, and that is forced by the data rather than chosen for convenience.** Fourteen tables reference `scholars(id)`, among them `transactions.creator`, which is `NOT NULL`. A scholar's participation is woven into other people's records: the transaction that paid a reviewer, the submission with co-authors, the thank-you note someone else received. Deleting the row would either fail on those constraints or destroy records belonging to other people. So the row survives as an anonymous tombstone — name, email, ORCID, free-text status, and the `auth.users` identity behind it are destroyed, and what remains is a uuid referring to nobody. That is what the terms already call transaction records being "de-linked".

**Erasure destroys the privilege along with the identity.** `forget_scholar` also clears `steward`, which it did not originally do. A tombstone that stayed a steward appeared on the public `/about` list as "anonymous" and still satisfied `isSteward()` — untidy on its own, and actively dangerous once `set_steward` existed, because a uuid nobody can sign into would have satisfied the last-steward guard and let the last real steward be demoted while nobody remained who could act. The fix lives in `forget_scholar` rather than in `set_steward` because [config.toml](supabase/config.toml) declares `schemas/scholars.sql` first and `schemas/erasures.sql` last, and a schema file may only reference tables declared above it.

The consequence is that the last steward can lock the platform out by erasing themselves, and `erase_scholar` is deliberately left unguarded against it: the right to erasure is an unconditional promise ([DESIGN.md](DESIGN.md)), and subordinating it to an operational convenience would be the wrong trade. `service_role` keeps table-level UPDATE on `scholars`, so recovery is a psql prompt away — which is the sort of thing to know before it is needed rather than after.

Two things are deliberately **not** erased:

- **The ledger's ownership columns.** An earlier sketch proposed nulling `token_events.scholar` and `prev_scholar`. Doing so would corrupt the ledger outright: `tokens_as_of()` reconstructs ownership from exactly those columns, so the most recent event for each of the scholar's tokens would claim no owner, `reconcile_ledger()`'s replay check would fail, and the tokens would become unexplainable. They hold uuids, which refer to nobody once the tombstone is scrubbed. Only `actor` is nulled.
- **The tokens themselves.** They are currency rather than personal data, and moving them would silently change a venue's reserve.

Every erasure is recorded in `public.erasures`, which has no foreign key to `scholars` so it outlives the row it names and survives a restore that predates it. Re-applying that list is a mandatory step of every restore.

## Backups

The database is dumped nightly at 08:00 UTC by [.github/workflows/backup.yml](.github/workflows/backup.yml) to S3-compatible object storage we control, independent of Supabase. **These run from `dev`**, not from `main`: GitHub fires `schedule` triggers only from the repository's default branch, and the default is `dev` (see [Branches](#branches)). So an edit to a backup workflow takes effect on the real nightly backup as soon as it lands on `dev` — before the release that would carry it to `main`. Nothing else in the repository behaves that way; treat these three files as production code wherever they sit. [RECOVERY.md](RECOVERY.md) is the operational document — provisioning, verification, and (from the next phase) the restore runbook. The mechanics live in [supabase/dr/dump.sh](supabase/dr/dump.sh), which is a standalone script rather than inline workflow steps so the nightly job, the pre-migration snapshot, and the rehearsal drill all capture byte-identical artifacts, and so it can be run from a laptop during an incident.

Four decisions worth knowing before touching any of it:

- **`pg_dump`, not `supabase db dump`.** The latter is scoped to the schemas it knows about, and this database is not restorable without `auth`: `public.scholars.id` references `auth.users(id) ON DELETE CASCADE`, so a `public`-only dump restores into a project with zero scholars. Custom-format archives are used throughout so a restore can be surgical (`pg_restore -t submissions`) instead of all-or-nothing.
- **Encryption is `age` in public-key mode.** Only the recipient's public key is in the repo; the private identity is held offline. The property that matters is that **CI can write backups but cannot read any backup, including the one it just made** — a compromised `GITHUB_TOKEN` yields nothing. `dump.sh` deletes its whole output directory if it fails before encryption completes, and the workflow independently refuses to upload anything that isn't `.age`.
- **Two pieces of state live outside every schema dump** and are captured on purpose: `cron.job` (exactly how `remind-daily` was silently lost once — see `supabase/migrations/20260517230819_restore_remind_cron.sql`) and the _names_ of the vault secrets. Vault **values** are never captured; they are set by hand on hosted projects and belong in a password manager, not in an artifact CI can write.
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
- **Combined.** `npm test` runs end2end, then unit, then the pgTAP suites — all three against the one local database, in that order. That is why an e2e test that corrupts shared state is not a local problem: it is the next suite's failure. See the token-ledger rule below.
- **What gates a pull request.** `ci.yml` (generated types + schema drift), `rls.yml` (all pgTAP), `vitest.yml`, and `locales.yml`. The last two were `workflow_call`-only and so ran first on the push to `dev` — i.e. after review had already passed, which meant a unit test could not actually block the change it was written for. Neither needs Supabase or a browser, so gating on them costs about a minute. Playwright still runs only on the push to `dev`, where the shard matrix is worth its runtime. [pr-target.yml](.github/workflows/pr-target.yml) also runs, but only for pull requests proposing to change `main`; it is not a required check, because a ruleset that requires one requires it of direct pushes too, and `npm run deploy` pushes the release commit to `main` directly.

E2E specifics:

- **Shared seed, shared helpers.** All specs share the one Supabase DB seeded by [supabase/seed.sql](supabase/seed.sql); use the `SEED` constants and `sql()` helper from [end2end/test-utils.ts](end2end/test-utils.ts) rather than re-declaring UUIDs or `psql` wrappers. Restore any shared row you mutate (usually in a `finally`). [end2end/global-setup.ts](end2end/global-setup.ts) resets the DB before each local run, so no manual `npm run reset` is needed.
- **Never write `public.tokens` directly.** Move value the way the app does — `mint_tokens`, `transfer_tokens`, `approve_transaction` — calling them as a particular scholar with `asScholar()` from [end2end/test-utils.ts](end2end/test-utils.ts), which supplies the `request.jwt.claims` those RPCs read through `auth.uid()`. A trigger logs every write to that table into `token_events`, so a raw `insert` is an unattributed mint and a raw `delete` logs a burn, after which the deleted tokens replay as owned by nobody. Neither breaks a Playwright assertion, which is exactly the problem: for a while three fixtures did this and `npm test` failed four pgTAP invariants on a clean tree, one suite later, on a database CI never assembles ([#152](https://github.com/reciprocalreviews/reciprocalapp/issues/152)). [end2end/global-teardown.ts](end2end/global-teardown.ts) now runs the replay diff and the unattributed-move count after every suite and fails the run, so the next one is caught where it happened rather than two suites downstream.
- **Hydration barrier.** Keep `waitForLoadState('networkidle')` before a Svelte interaction (card-expand click, bound `fill`) — on this SSR app the page looks ready before handlers are wired, so an early click is silently dropped. Only safe to drop before a pure assertion.
- **Auth** in tests uses a local-only email+password grant against the seeded users (`login()`/`logout()` in [src/routes/login.ts](src/routes/login.ts)); the seed gives every user a known password. The dev sign-in forms render only when `PUBLIC_SUPABASE_URL` points at a local stack — **not** merely when `PUBLIC_ENV !== 'prod'`. Staging is non-prod but points at a hosted project, and it is the one environment that can validate custom OIDC before production, so it must exercise the real ORCID path rather than a mock (and not accumulate throwaway `@orcid.example` users). ORCID custom OIDC can't run in local Supabase, so the real redirect/callback is exercised only in hosted staging against the ORCID sandbox. Behind the same gate, the login page offers three things, in the order you reach for them. A **table of the seeded scholars** — name, address, and what each can do (steward / venue admin / currency minter) — for one-click sign-in, so exercising a flow as a particular scholar doesn't mean opening `seed.sql`. The shared password lives in [src/lib/auth/devPassword.ts](src/lib/auth/devPassword.ts) so the page and the Playwright helper cannot drift; it is not in the helper itself because that module imports `@playwright/test` and the application must not pull test code into its bundle.

  The helper reaches that file by a **relative** path rather than the `$lib` alias, and has to. Everything else in `src/` is loaded by Vite, which resolves the aliases from `svelte.config.js`; this one module is loaded by Playwright through Node, which knows nothing about them. Playwright can map an alias, but only from the `paths` in `.svelte-kit/tsconfig.json` — a generated file that does not exist in a fresh checkout, and that it reads once when the process starts. `emu` runs `svelte-kit sync`, but as the `webServer` command, which is far too late. So the alias worked on any machine that had ever run the dev server and failed everywhere else, including every CI runner: all four shards collected zero tests and the deploy never reached `migrate` or `vercel`. It is the one file in the repo where an alias is a liability rather than a convenience.

Below it, the **email + password form**, kept because two kinds of account are unreachable from the table, and kept _visible_ for a third reason. The table signs in with `scholars.email`, which is a _contact_ address rather than the auth identity: the seed sets both alike, but a scholar who later verifies a different address can no longer be signed in this way (each row shows the address it will use, so this is visible rather than mysterious), and a scholar created by the control below has no contact address at all and so never appears. As for visibility — `gotoLogin()` waits for `email-input` to be _visible_ as its hydration barrier, and `login()` fills it, so putting the form inside a collapsed `Card` would add an expand click to the critical path of all 69 `login()` calls and 17 `logout()` calls. Tidiness on a dev-only page does not justify that.

Last, and deliberately last, the **create-a-scholar** card. It is not a sign-in: `signInWithMockORCID` calls `signUp`, which fires `handle_new_scholar` and produces the null-email first-run state — the only way to reach onboarding, since every seeded scholar already exists. It sat at the top of the page for a while, labelled as an ORCID sign-in, which read as the primary way in and made the two controls below it look redundant.

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
