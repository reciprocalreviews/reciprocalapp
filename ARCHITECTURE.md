# Architecture

_Last revised: 2026-09-13_

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

The Vercel function is pinned to **`sfo1`** ([svelte.config.js](svelte.config.js)`#adapter`), because the Supabase project is in **AWS `us-west-1`**. They are a pair: the function defaulted to `iad1`, which made every server-side query a cross-country round trip of roughly 130ms, and a load that runs two of them serially paid it twice. Moving either side without the other reintroduces that. `regions` belongs in the adapter options rather than [vercel.json](vercel.json) — the adapter writes it into the function's `.vc-config.json`, which is what the Build Output API actually reads.

Reads are gated by Postgres row-level security, so the database is the last line of defense regardless of what the client requests. Writes that should produce email enqueue rows in the `emails` table; an Edge Function consumes them and posts to Resend in production (or logs to the console in local dev).

### Shared and private responses

Four routes — `/`, `/[[lang]]/terms`, `/[[lang]]/updates`, `/[[lang]]/help` — render the
same HTML for every anonymous visitor, and are listed in `PUBLICLY_CACHEABLE` in
[hooks.server.ts](src/hooks.server.ts). For a request carrying no Supabase session cookie
they are returned `public, max-age=0, s-maxage=3600, stale-while-revalidate=86400` with
`Vary: cookie`, so Vercel's CDN serves them without invoking the function; for a request
carrying one they are returned `private, no-store` and rendered for real.

They used to be `prerender = true` instead. That was free, but it ran
[+layout.server.ts](src/routes/+layout.server.ts) at build time against a request with no
cookies, so `cookies: []` was baked into the shipped payload and a signed-in scholar
landed on the anonymous header until hydration replaced it. Per-request rendering plus
per-request caching keeps the anonymous path off the function while giving a signed-in
scholar a correct header in the first byte.

Four details hold it together, and none of them is optional:

- **The decision lives in the hook, not in a `load` calling `setHeaders`.** Kit applies
  `setHeaders` values and _then_ `Set-Cookie` inside the `resolve()` that `handle` awaits,
  so a load cannot see a cookie it is about to set and the hook can. A response that sets
  any cookie is therefore never marked public — the interlock against caching a session.
- **`Vary: cookie`, on both branches.** A request bearing cookies can never match the
  entry cached for requests bearing none.
- **`max-age=0` beside `s-maxage`.** The shared cache may keep the anonymous copy; the
  browser may not, or a visitor who signs in would be served it from their own disk cache,
  where no request happens and nothing can correct it.
- **Matching on `event.route.id`, not the pathname.** `[[lang]]` is optional and
  unconstrained, so `/terms`, `/en/terms` and `/anything/terms` all resolve to
  `/[[lang]]/terms`.

Why this matters beyond the four routes: `+layout.server.ts` serializes the session
cookies, JWT included, into the HTML and into every `__data.json`. Anything that becomes
publicly cacheable while carrying that payload hands one scholar's session to whoever asks
next. **Adding a route to `PUBLICLY_CACHEABLE` is a claim that its output is identical for
every anonymous visitor** — and adding anything personalized to a route already on the
list breaks that claim silently.

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
- **Expired-session handling.** When a session dies (token expiry, a revoked refresh token, or a local DB reset), the scholar is sent to `/login` instead of being left on an authenticated page where every write fails with a cryptic RLS/permission error. Two hooks cover it, gated by [`requiresAuth()`](src/lib/auth/requiresAuth.ts) (public routes — landing, login, about, help, contact, brand, terms, updates, verify — are exempt; every page the footer links to belongs on that list, since a broken session is exactly when someone reaches for them): the layout load ([+layout.ts](src/routes/+layout.ts)) redirects when an auth cookie is present but `getClaims()` yields no user (a present-but-invalid session — distinct from an anonymous visitor, who has no cookie and is not redirected); and the `onAuthStateChange` listener in [+layout.svelte](src/routes/+layout.svelte) redirects on a live `SIGNED_OUT` event.

**Contact email + verification (app-level, #27).** Because ORCID carries no email, a scholar's contact email is collected separately and its ownership verified in-app — independent of Supabase auth. `scholars.email` holds only a **verified** address (or null). Two things enforce that, and both are needed: it is written solely by the `verify_email` RPC, and the column privilege to write it is revoked (see Column privileges below).

A logged-in scholar with no verified email sees a persistent banner ([Banners.svelte](src/lib/components/Banners.svelte)) and receives no notifications. Requesting or changing an email (`requestEmailVerification` in [SupabaseCRUD](src/lib/data/SupabaseCRUD.svelte.ts)) calls the `request_email_verification` RPC, which does everything inside the database: it stores a pending candidate and a sha256 token hash in `email_verifications` (deny-all RLS, **24-hour** expiry, one active request per scholar, one-minute cooldown), builds the link from the `site_url` vault secret, and queues the branded email itself, recording which `emails` row carried the link in `email_id`.

**The window is 24 hours, not fifteen minutes, because the clock starts at the wrong end** ([#164](https://github.com/reciprocalreviews/reciprocalapp/issues/164)). `expires_at` is set when the row is written, but between that instant and a readable message sit a best-effort `net.http_post`, an edge function cold start, Resend's queue, and the recipient's mail server — university greylisting alone routinely adds five to fifteen minutes. A quarter-hour budget could be spent before the link was reachable. The blast radius argues the same way: a 256-bit token that never appears on screen and grants only "set my contact address" is not a password reset.

**The RPC returns nothing.** The raw token never reaches the client, and the caller supplies neither the message body nor the link's origin. Each of those is load-bearing: returning the token let anyone read it from the network tab and confirm an address they did not control; a caller-supplied body plus a caller-chosen recipient is an open relay; and a caller-supplied origin would put a link to a host of their choosing inside genuinely branded mail. The queued row is written with a **null `scholar` and `sender`** so that no branch of the `emails` SELECT policy matches it — otherwise the requester could read the token straight back out of the row.

The anon-callable `verify_email` RPC ([src/routes/[[lang]]/verify/[token]/+page.server.ts](src/routes/[[lang]]/verify/[token]/+page.server.ts)) validates the token and commits the candidate into `scholars.email`. It deliberately does **not** delete the request: verification is idempotent within the 24-hour window, so an email security scanner or a link prefetch cannot burn the link before the scholar clicks it.

**Nor does it delete on expiry any more, which is what makes a resend possible** ([#164](https://github.com/reciprocalreviews/reciprocalapp/issues/164)). Deleting the lapsed row threw away the only record that a scholar had ever asked for anything — and with `email_verifications` under deny-all RLS and no read RPC, the application had no memory of a pending verification at all. A scholar who missed the window came back to an empty form, with no sign of which address was waiting and no way to ask for another; the expired page could only tell them to "request a new one from your profile". The row now survives both endings, so `verified_at` rather than the row's existence is what answers "is something pending?", and a confirmed request is checked **before** the clock — otherwise reopening a two-day-old message would report an expiry for an address that is already theirs. Retention is bounded by construction: `scholar` is the primary key, so a later request replaces the row rather than adding to it, and the table cannot grow past the number of scholars.

`pending_email_verification` is the read half, and the reason the row is kept. It answers for `auth.uid()`, takes no argument, and returns the caller's candidate address, its timestamps, whether it has lapsed, the instant the cooldown lifts, and the coarse delivery status of its message — and **nothing else**. Three omissions are deliberate and asserted in [email_verifications_rls.sql](supabase/tests/rls/email_verifications_rls.sql), which pins the whole key set rather than three absences: the token hash (the secret the design exists to keep inside the database), `email_id` (it names a row whose `args` carry the raw link), and `delivery_detail` (edge-function diagnostics that can quote a payload). The cooldown comes back as an **instant** rather than a duration so the interface counts down to the moment the RPC starts accepting again, instead of re-deriving "one minute" in the browser and disagreeing with the database by a second — the difference between a button that works when it lights up and one that answers with an error. [VerifyEmail.svelte](src/lib/components/VerifyEmail.svelte) renders it on the profile and on the expired-link page; on the latter the RPC's own `42501` **is** the signed-out test, since `EXECUTE` is revoked from `anon`, so no session check has to be plumbed into a route that is deliberately exempt from the auth redirect.

Erasure has to reach these messages specially. The `VerifyEmail` row is attributed to nobody, so the redaction pass keyed on `scholar`/`sender` never matched it, and an erased scholar's unverified candidate address and raw verification URL survived indefinitely; `forget_scholar` now redacts by `email_id` before deleting the request.

**Column privileges on `scholars`.** The update policy authorizes the row but says nothing about columns, and `grant all` gave `authenticated` a table-wide UPDATE — so a scholar could set `steward = true` on themselves, rewrite `orcid` to claim another researcher's identity, or set `email` directly and skip verification entirely. Because a column-level revoke is a no-op while the table-level privilege stands (as in [20260601000000_rls_corrections.sql](supabase/migrations/20260601000000_rls_corrections.sql)), the table UPDATE is revoked and only `name`, `available`, `status`, `status_time` are re-granted. `email` is written by `verify_email` and `status_reminder_time` by the remind function, both of which bypass these grants. Covered by [scholars_columns_rls.sql](supabase/tests/rls/scholars_columns_rls.sql) — the pre-existing row-level tests all passed while this was open.

That narrowing left `steward` writable by nobody, which was correct and also meant stewardship could only be conferred at a psql prompt. The tool that migration deferred — "a `SECURITY DEFINER` RPC gated on `isSteward()`, not a blanket table privilege" — is [set_steward](supabase/migrations/20260818000000_set_steward.sql), and the column grants are deliberately untouched, because they are what makes it the only path. Two guards protect the floor: nobody may demote themselves, so stepping down is always an act another steward performs; and the last steward may not be demoted at all. The second looks unreachable and is not — serially it is, since demoting X requires a steward caller other than X, so one always survives. It earns its place concurrently, and only alongside the row lock the function takes before deciding anything: under `READ COMMITTED` two stewards demoting each other would each see the other still standing, and both would succeed. Covered by [set_steward_rpc.sql](supabase/tests/rpc/set_steward_rpc.sql), which also re-asserts that the column grant is still narrow — if that ever passes, every guard above can be walked around.

## Data access

All database I/O — both the write path and the page-load read path — goes through an abstract interface, not the Supabase client directly. This keeps route code free of database-specific concerns and makes the backend swappable or mockable.

- The interface is [src/lib/data/CRUD.ts](src/lib/data/CRUD.ts).
- The Supabase implementation is [src/lib/data/SupabaseCRUD.svelte.ts](src/lib/data/SupabaseCRUD.svelte.ts). The root [src/routes/+layout.ts](src/routes/+layout.ts) builds a single instance, returns it as the `db` load datum, and the root `+layout.svelte` exposes that same instance via `setDB()` / `getDB()`.
- **Writes** return `Result<T> = { data?: T; error?: DBError; notified?: Notification[] }`. The `handle()` helper in `src/routes/feedback.svelte.ts` wraps calls and posts errors to the global feedback bus, so component code is typically `await handle(db().someMethod(...))`.
- **A batch of notifications becomes one banner.** Each `Notification` may carry a `group` key, and [notifications.ts](src/lib/data/notifications.ts) collapses a group of more than `GROUP_MAX` (3) into a single banner naming its first entry and counting the rest — the same rule DESIGN.md already applies to mail, where a bulk import sends one message rather than one per row. It exists because `handle()` posted one banner per entry into a stack with no cap and no auto-dismiss, inside the sticky header: a call for bids to a three-hundred-volunteer role produced three hundred bars, pushed `main` below all of them, inflated the `--nav-height` that `Page.svelte` and `scroll-padding-block-start` depend on, and covered the nav controls — which is why three e2e tests still drain the stack by hand before clicking logout. The key is the email template name, set in `queueEmail`, so `inviteToRole`'s loop of single-recipient sends collapses as one batch even though each send resolves separately. Collapsing never yields zero banners: only two of the app's ~76 `handle()` call sites pass a success string, so for the rest these notifications are the only evidence the action did anything. The count matters as much as the name — `queue_email` skips scholars with no verified address and anyone who opted out, so who was emailed is not who was asked, and the number is how that difference stays visible. The collapsed wording is written by the **producer**, not assembled by the feedback layer: a plural is not a suffix — "was emailed" has to become "were emailed" — and the producer is also the only place with locale. It travels on the notification as `collapsed`, still carrying its `{count}` placeholder, because the batch size is not knowable where it is built (`inviteToRole` reaches `queueEmail` once per invitee, each call seeing one recipient); the feedback layer fills the count once it has seen the whole batch. A group whose producer supplied no plural still collapses, falling back to appending a count to the singular — worse prose, but it never shows one message speaking silently for three hundred people. The rules are a pure function so they can be tested without a component or a stubbed `$app/navigation`.
- **Reads used by load functions** return `ReadResult<T> = { data: T; error?: DBError }` — `data` is always present (null on a missing row or a failed query) so loads can destructure `data` with the same nullability the raw query builder gave them. Read failures are logged by the implementation, not surfaced. Load functions obtain the instance via `const { db } = await parent()` and call `db.getX(...)`; they never touch the query builder ([#137](https://github.com/reciprocalreviews/reciprocalapp/issues/137)).
- The raw Supabase client is **not** returned as load data. It is reachable only through `db.client`, the single sanctioned escape hatch, used only by auth (`+layout.svelte`, `getClaims()`) and realtime ([src/lib/data/SupabaseRealtime.ts](src/lib/data/SupabaseRealtime.ts)).

New domain operations should be added as methods on the `CRUD` interface and implemented on `SupabaseCRUD`, never as ad-hoc Supabase calls in a route.

**A filter built by hand must quote its values.** Most reads use the query builder's own `eq` and `in`, which encode their arguments. Two do not, because matching one typed string against two columns in a single round trip means composing an `or()` filter — and `or()` takes a string, so its values are concatenated in: `findScholarsByAddresses` and `findScholar`. Values interpolated into one go through [postgrestFilter.ts](src/lib/data/postgrestFilter.ts), which always double-quotes and backslash-escapes `"` and `\`. That is deliberately stricter than supabase-js's own `in()`, which quotes only when a value contains `,`, `(`, or `)` and escapes nothing at all — so it is not the reference implementation to copy. The escaping is not hypothetical: `validEmail` permits a quote in a local part, so `a"b@c.co` is an address the role-invite field accepts, and wrapped in bare quotes it closes the value early and the remainder is read as filter syntax.

Relatedly, every scholar query names its columns rather than using a bare `select()`. The `scholars` SELECT policy is `using (true)`, so a wildcard hands out every column of any row a caller can name — including contact addresses to anyone who can type into a name field.

**A field of several searches caches its answers by query text, not by position.** `ScholarSearch` asks one question over and over, so it carries a sequence number: a slow earlier answer really can overwrite a later one. The role invite asks several questions at once and keys its answers by the exact query string, so editing the first query leaves the second one's answer alone and a late answer lands under the question it was about. That removes staleness handling entirely; the only guard left is a teardown flag. It also decides how the queries are sent: addresses and ORCID iDs go in one batched `findScholarsByAddresses`, but names go one `findScholarsByName` each, because `scholarsByNameQuery`'s `limit(3)` is per query and PostgREST cannot express a per-branch limit inside an `or()` — merged, three matches for the first name would leave nothing for the rest. If that burst ever matters, the escape hatch is a `find_scholars_by_names(text[])` RPC with a `lateral` join and a per-name limit.

### Atomic operations

Operations that perform more than one write — minting or moving tokens, recording a payment alongside the tokens it moves, provisioning a venue — run as `SECURITY DEFINER` Postgres RPCs so each completes in a single transaction; a connectivity loss can no longer leave partial state (tokens moved with no transaction recorded, a submission with orphaned proposed payments, a half-provisioned venue). The CRUD method resolves/validates inputs (reads), calls the RPC for the atomic write, and surfaces the result. Because `SECURITY DEFINER` bypasses RLS, each RPC re-implements its tables' authorization and anti-self-dealing rules in its own body.

The atomic RPCs are `mint_tokens`, `transfer_tokens`, `approve_transaction`, `create_submission`, `create_volunteer` / `accept_role_invite` (volunteer record plus its welcome grant), and `approve_venue_proposal` ([#136](https://github.com/reciprocalreviews/reciprocalapp/issues/136)), alongside the pre-existing `complete_assignment`, `mark_submission_done`, and `bulk_import_submissions`. Each is defined in a migration and mirrored into the relevant `supabase/schemas/` file so it sits next to the table it operates on.

**Every path that moves existing value goes through one function**, [`public._move_tokens`](supabase/schemas/tokens.sql) ([20260830000000](supabase/migrations/20260830000000_token_scaling_phase1.sql)). Six RPCs used to pick tokens with `select id from tokens where <holder> order by id limit N` and then move them with `update ... where id = any(_token_ids)` — no lock on the select, and no ownership predicate on the update. Under `READ COMMITTED` two concurrent draws on the same holder see the same snapshot and, because the order was `id` and therefore deterministic, select **the same rows**; the second update blocks on the first's row locks and then, since `id = any(...)` is still true once the first commits, overwrites them. Both callers report success and both write a `transactions` row, but the first recipient's tokens are gone. The holder's `count(*)` stays consistent, which is why nothing noticed — only `reconcile_ledger`'s conservation check would have caught it, a day later. Reproduced before the fix with a 50-token reserve and two sessions each drawing 25: both reported moving 25, and the first scholar ended up holding 0. It also owns the one case where value is _created_ rather than moved: `_mint_shortfall` mints what a reserve cannot cover, and since [20260902000000](supabase/migrations/20260902000000_shortfall_mints_are_recorded.sql) it takes `_mint_creator` and `_mint_purpose` and **refuses to mint without them**, recording an approved mint transaction crediting the reserve and saving and restoring the caller's `app.txn` so the mint and the move file under different transactions. The defect it replaced was a caller forgetting to record the credit, so the guard makes forgetting impossible rather than merely discouraged.

`_move_tokens` takes its rows `for update skip locked` and re-asserts the source's ownership in the `UPDATE` itself. `SKIP LOCKED` rather than a plain `FOR UPDATE` because blocking would serialize every payout in a busy venue behind one another; skipping makes concurrent draws disjoint and turns `RR003` from "the holder lacks the tokens" into "the holder lacks _available_ tokens", which is the accurate claim and is retryable. It also carries no `ORDER BY`: tokens are fungible, so the ordering pinned nothing observable, while making concurrent draws contend for exactly the same lowest ids and talking the planner out of the composite indexes onto a `tokens_pkey` walk past every token already spent — 35ms per transfer on a 500,000-token fixture against 0.05ms without it. **A seventh token-moving RPC must call `_move_tokens` rather than reimplement the select-then-update.** [supabase/tests/rpc/move_tokens_rpc.sql](supabase/tests/rpc/move_tokens_rpc.sql) pins the contract, including a structural assertion that the locking clause is still there.

Balances are `count(*)` over `tokens`, and the app used to read them by fetching one row per token and taking the array length in the browser. PostgREST caps a response at `max_rows` (1000) and truncation is not an error, so those counts silently stopped at 1000: a quarter-million-token reserve reported 1000, and the affordability check refused submissions their authors could pay for. Counting now happens in the database — `currency_holder_counts`, `scholar_balances`, and `{ count: 'exact', head: true }` at the call sites.

`_welcome_volunteer` (the helper behind `create_volunteer` / `accept_role_invite`) moves real tokens rather than recording a proposal. It used to insert a _proposed_ venue→scholar transaction of placeholder UUIDs for a minter to approve later, which contradicted DESIGN's "minted and given" and put a human approval between a newcomer and the tokens they had just volunteered to earn — most painfully for someone volunteering in order to afford a submission. It now mirrors `approve_transaction`'s venue-source branch: draw from the venue's reserve, mint only the shortfall into the reserve first, move the tokens, and record one **approved** transaction. It records a **second** approved transaction too, crediting the reserve for the tokens the shortfall minted — and that is the part that was missing until [20260902000000](supabase/migrations/20260902000000_shortfall_mints_are_recorded.sql). Both token writes were attributed through `app.txn`, and that was mistaken for the whole story. Attribution says which transaction _touched_ a token; conservation asks whether anyone was _credited_ for its creation. The shortfall mint was attributed and uncredited, so every venue whose reserve ever ran short held tokens its own history did not account for, with `expected` sitting permanently below `actual` by the number minted. Production's nightly check found it on 2026-08-30; see §reconcile_ledger. It returns the number of tokens granted (0 on each no-op path) and both callers pass that back as `welcome_granted`, so the confirmation can state the amount instead of promising tokens that may never have been granted — the three conditions that decide it are not ones the client can evaluate without re-deriving the rule. Changing a function's return type is not something `create or replace` will do, so the migration drops it first. The first of those conditions is scoped to the venue: `create_volunteer` and `accept_role_invite` count the scholar's existing volunteer rows through a join on `roles.venueid`, because `welcome_amount` is one venue's standing policy in one venue's currency. They previously counted volunteer rows platform-wide, so a scholar who had ever volunteered anywhere received nothing at every venue they joined afterward — silently, since the grant's only outward sign is the amount in the confirmation.

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

The mirror of that rule applies to components that cache **server** data: cache only what the prop cannot supply, and key the cache on something that changes whenever the cache is actually invalid. [src/lib/components/Transactions.svelte](src/lib/components/Transactions.svelte) is the example. It renders the first page straight from the prop and caches only pages 1..n, which it pages in by absolute offset and so cannot get from anywhere else. It once cached the first page too, keyed on the row ids — and a row's mutable fields don't change its id, so approving a transaction left the row rendering as proposed with its Approve button still live. A cache key can only describe the fields someone thought to name; not caching what the prop already holds is what makes the whole class of staleness unrepresentable.

`handle()` **awaits** that `invalidateAll()`, so it resolves only once the load functions have rerun and the page data reflects the write. That matters to anything that reads a prop straight after saving: while it returned early, every caller was handed "success" while its props were still the pre-write values, and a component that synced from them at that moment showed the old text until the refetch landed and then flipped to the new one. Because the data is current by the time the promise settles, a component may take its value back from the prop on success — which is also how it learns when the server kept something other than what was typed, as `VerifyEmail` does by leaving the stored address alone until the new one is verified.

## ORCID profile mirror

`public.orcid_profiles` caches the narrow slice of a scholar's **public** ORCID record that
DESIGN.md's Scholar route describes. One row per scholar, keyed on the scholar rather than
the iD so PostgREST can embed it from any query that already has `scholars` in it.

**Why a cache at all, rather than fetching on view.** Three of the four surfaces that show
it are lists — the volunteers roster, the assignment table, the assignment form — and a
list cannot fetch per row. Fetching on view would also put a third party's availability on
the critical path of a page that already runs a dozen queries.

**Where the fetch runs.** `supabase/functions/orcid/`, called from Postgres over `pg_net`,
authorized by the same `secret_key` vault secret and `requireSecretKey` gate as `resend`
and `remind`. Two alternatives were weighed and rejected: a SvelteKit `+server.ts` route
cannot write the table, because nothing under `src/` holds a privileged key and adding one
would be the first server-side secret in the app; and `pg_net` straight from the database
would put ORCID's deeply nested JSON into plpgsql, where vitest cannot reach it. The shape
is `send_email()`'s, deliberately: a database event fires a best-effort post and never rolls
back its caller.

The parser lives in `supabase/functions/_shared/orcidProfile.ts` and is re-exported from
`src/lib/data/orcidProfile.ts`, the same split as `_shared/emailShell.ts` — Deno bundles
only what is under `supabase/functions`, and vitest collects only `src/**/*.unit.ts`. The
shared module must stay dependency-free pure TypeScript; a Deno global in it breaks the
Vite build of the whole app. The edge function is a thin shell around it on purpose: there
is no test harness for edge functions in this repo, so logic that lives there is logic
nothing checks.

**Claiming, and why the order matters.** `private.claim_orcid_refresh` stamps
`fetch_attempted_at` **before** asking the function for anything. That is what makes the
six-hour cooldown a stampede guard rather than a hope: ten editors opening the same roster
claim once between them. `public.request_orcid_refresh` is the authenticated entry point,
clamped to one batch; `public.backfill_orcid_profiles` is the steward-gated bootstrap,
which takes the oldest never-fetched slice and is re-runnable until it returns 0. `_force`
bypasses the staleness clocks but never the cooldown, so no caller can turn any of this
into a flood.

**Two clocks.** Profile sections refresh at 30 days, works at 90. Works are the only
expensive fetch — 787KB uncompressed for a prolific record against 8.3KB for the other
three sections combined — so they are asked for per scholar only when their own clock has
expired. `Accept-Encoding: gzip` cuts that 13–21×, and it is the only bandwidth lever
there is: ORCID sends no `ETag`, no `Last-Modified`, and ignores `If-Modified-Since`.

**The counting trap.** `/works` returns groups, and each group holds one summary per source
that claimed the work — Crossref, Scopus, the scholar themselves. `work_count` is the number
of GROUPS. A real record measured here holds 46 works across 50 summaries, so counting
summaries would report a number visibly wrong to the person it describes. The preferred
summary within a group is picked by how much of what RR displays it carries, then by
put-code, because row order within a group is not guaranteed between responses.

**Failure is always terminal in the row**, so the cooldown always advances: `ok`,
`not_found` (404/409, cached rather than retried forever), or `error` with a failure count
driving backoff. Partial success is per-section — if `/person` answers and `/employments`
fails, the keywords are written and the employment columns are left alone, because a
partially refreshed row is strictly better than one emptied by an unrelated failure.

**Deliberately not:**

- **Not audited.** `log_audit_event()`'s no-op skip compares whole rows and
  `fetch_attempted_at` changes on every refresh, so this would instantly become the audit
  log's highest-volume writer — into a table already documented as more sensitive than any
  it records. Nobody will ever ask who changed one of these rows; the answer is always the
  edge function. And the recovery argument does not apply: this is the one table in the
  schema that a restore can simply re-fetch.
- **Not in the realtime publication.** `SupabaseRealtime` calls `invalidateAll()` on
  changes, so a batch refresh would reload every subscribed client for data nobody is
  watching.
- **Not writable by anyone.** No INSERT, UPDATE or DELETE policy exists, and the table-wide
  grants are explicitly revoked from `anon` and `authenticated` before the SELECT grant —
  Supabase's default privileges hand out ALL on every new table in `public` first.
- **Not warmed by anonymous visitors.** `request_orcid_refresh` is `authenticated`-only, so
  an anonymous visitor to a cold profile sees the ORCID link and nothing else. The editors
  this exists for are always signed in, and leaving anon out closes a crawler-driven path
  into ORCID's daily budget.
- **No cron job.** The read-driven claim plus the steward backfill covers it; see Scheduled
  jobs below.

**Populating it.** `backfill_orcid_profiles` is steward-gated and reachable from a card on
`/about`. It needs a UI because the obvious alternative does not work: a steward running the
function in a SQL editor is refused, since there is no `auth.uid()` in that session and the
function checks `isSteward()`.

**Rate limits.** The anonymous public API allows 12 requests a second and 25k reads a day
**per IP**, and edge egress IPs are shared. Registering a free Public API client raises the
daily cap to 100k and makes the budget ours rather than the IP's; the code adds an
`Authorization` header only if an `orcid_public_token` vault secret exists, so the
secret-free path stays the tested default.

## Email pipeline

Email is **application email** — transactional, reminder, and contact-email verification — all sharing one branded visual identity, and all replyable: a send carries `Reply-To: stewards@reciprocal.reviews` (see Addresses below) unless the row names its own, which the new-volunteer notice and the call for bids do. The branded footer follows the header rather than repeating a fixed sentence, so a message that replies to a person says so and names `stewards@` separately as the route to support; `renderBrandedEmail`'s `replyTo` argument is trailing and optional, so the `remind` cron keeps the default without changing. Its `copied` argument is trailing for the same reason, and decides whether the footer mentions **Reply All** at all. That clause used to be unconditional, which was true of the only message carrying its own `Reply-To` at the time — the new-volunteer notice, addressed to one holder of a venue's top role and copying the rest. It is false of a call for bids, which is N private copies on purpose, and false of a new-volunteer notice at a venue with a single holder. Only the `resend` consumer knows the row's `cc`, so it is the one caller that answers the question. This is the same rule the custom footer exists to serve: a footer the reader would believe, pointing at a group that does not exist, is worse than no footer at all. (Supabase GoTrue no longer sends auth email: sign-in is ORCID and email verification is app-level, so the auth-email path is dormant — see below.) Templates are English only: there is no mechanism yet to solicit a scholar's language preference.

### Application emails

Server code never calls Resend directly. The producer / consumer split is:

1. **Producer.** Application code calls `emailScholars(scholars, templateKey, args)` (in [SupabaseCRUD](src/lib/data/SupabaseCRUD.svelte.ts)), which goes through the `queue_email` RPC. **Direct INSERT into `emails` is revoked** from `authenticated` and `anon`: inserting a row sends branded mail, so an insert policy meant any signed-in user could name any recipient with any body — an open relay from `notifications@reciprocal.reviews`, and self-service ORCID sign-up makes "authenticated" a low bar. `queue_email` resolves recipients server-side from scholar ids (skipping anyone without a verified contact email, which is what enforces "never notify an unverified address", and anyone who has silenced the notice — see Optional notices) or, for `ProposalCreatedEditors`, from the proposal's own editor list. It accepts **no message body at all**. There are two siblings: `queue_steward_email` for mail to the steward alias, and `queue_reminder_email` for the cron, which has no `auth.uid()` to offer and so cannot use `queue_email` itself.
2. **Consumer — `resend` function.** [supabase/functions/resend/](supabase/functions/resend/) posts to the Resend API, wrapping the body in the shared branded HTML shell ([supabase/functions/\_shared/emailShell.ts](supabase/functions/_shared/emailShell.ts)) and sending both an HTML and a text/plain alternative. In local dev (when `PUBLIC_SUPABASE_URL` points at 127.0.0.1) it logs to the console instead. **It requires the caller to present one of the project's secret keys** ([\_shared/auth.ts](supabase/functions/_shared/auth.ts)) — see Edge function authorization below. The `remind` function carries the same guard.
3. **Recipients are a list, not a name.** `emails` carries `cc text[]` and `reply_to text` alongside `email`, so a notice meant to be _one shared thread_ is one row and one send — the first recipient addressed, the rest copied — rather than N messages that never converge. Both are more recipient surface than `to`, so the open-relay rule tightens rather than loosens around them: neither may ever be written from a value that crossed the API. `queue_email` and `queue_steward_email` take no parameter for either, and the only writer is `_notify_new_volunteer`, which resolves every address from `scholars.email`. `cc` is null rather than empty when there is nobody to copy (a `CHECK` enforces it), because Resend treats `cc: []` as a malformed field and rejects the whole send — a rejection `pg_net` swallows, so the mail would vanish rather than fail.

   Two things key on addresses rather than ids and so had to learn about these columns: `forget_scholar` scrubbed `where scholar = … or sender = …`, which matches neither, so an erased address would have survived in mail about other people; and `export_scholar_data` reported only mail addressed to a scholar, omitting notices they were copied on. Both now resolve the address first — in erasure's case _before_ `scholars.email` is nulled, which is the only reason it is still reachable.

4. **Rendering happens at send time, not at the call site.** Rows carry `event` + `args`; the `resend` function renders them from the registry, which now lives at [supabase/functions/\_shared/templates.ts](supabase/functions/_shared/templates.ts) (re-exported from `src/email/templates.ts` for app code) so both runtimes share one source of truth. `subject`/`message` are nullable and null for such rows — `event` + `args` is a complete, re-renderable record. A caller can choose the template and its argument _values_ but cannot author prose, and `renderEmail` defangs URL schemes in argument values (`https://x` → `https[:]//x`) so a supplied value cannot become a clickable link inside branded mail. Templates opt specific positions out via `urlArgs` when the link is server-generated — only `VerifyEmail` does, which is why `queue_email` refuses to queue it.
5. **Reminder cron — `remind` function.** [supabase/functions/remind/](supabase/functions/remind/) is invoked daily at 22:00 UTC by a `pg_cron` job (`remind-daily`) defined in `supabase/migrations/`. It emails scholars with stale availability (fixed 90-day staleness, 30-day dedupe), and runs venue-scoped reminder families in `getVenueReminders`, all sharing one cadence gate — `venues.transaction_reminder_frequency_days`, stamped to `venues.transaction_reminder_time`, stamped for every due venue including those with nothing outstanding so the frequency is honored rather than re-checked daily. It is the only producer that runs outside the SvelteKit process.

   It used to be the only producer outside the **pipeline** as well: it wrote its own subjects and paragraphs and posted them straight to Resend, never touching `public.emails`. That single fact caused four separate problems — the reminders could not be silenced, they left no row in the mail log, they got no delivery reconciliation, and they were missing from the `export_scholar_data` download that is supposed to count every message a scholar was sent. They now render from the registry like everything else and go in through `queue_reminder_email`, so all four follow from going through the table rather than needing four fixes. Nothing in the cron builds a link's origin any more either; templates own their URLs and `{origin}` is resolved at send time, the same as for every other email.

   The families are: proposed **venue-sourced** transactions → admins + minters; proposed **scholar-sourced** charges → the charged scholar (a co-author's unpaid share; the earlier code skipped these with `if (!transaction.from_venue) continue`, so the one person who could pay was the one person never asked again); **requested compensation** → the approver union; **submissions ready to mark done** → their priority-0 editors; and **submissions still waiting for an editor** → the venue's editors and admins.

   Two of them reuse an existing preference rather than owning one, because chasing a thing is the same subscription as being told about it: the editor-waiting reminder reuses the `SubmissionsNeedEditors` template outright, and `CompensationPending` defers to `CompensationRequested`. Only `SubmissionChargeReminder` is consequential — nobody opts out of being told they owe money, and that reminder exists precisely because the first notice can be missed. Three families used to gather a scholar's links from every venue into one message; their templates are venue-scoped, so the grouping is too, and somebody who admins three venues now gets three messages that are each actionable rather than one that is not.

   Two of those deserve their rules stated, because both are about _not_ sending mail. Compensation reminders key on `assignments.compensation_requested_at` rather than on `approved and not completed`: the latter describes a review still in progress just as well as it describes finished work, and a reminder that fires on both is one approvers learn to delete. Ready-to-mark-done reproduces `mark_submission_done`'s own blocker rule — every approved non-editor assignment compensated, at least one of them actually compensated, and an uncompleted priority-0 assignment to notify — so the reminder cannot suggest an action the RPC would refuse. The approver union is the same three branches as `can_approve_assignment` (venue admins, the submission's priority-0 assignees, holders of the role's approver), computed in TypeScript here because the function reads with `service_role` and so gets no help from the policies.

6. **Server-side fan-out — thank-you notes.** Author thank-you notes to reviewers (#22; the `thanks` table, vetting toggled by `venues.vet_thanks`) need privileged recipient resolution: the author may not see who reviewed their submission. The note bodies are still rendered from the `Emails` registry in `templates.ts` like every other email (`ThanksPendingReview` / `ThanksReceived` / `ThanksDeclined`), but the fan-out goes through the `queue_thanks_emails` RPC (`SECURITY DEFINER`) instead of `emailScholars`. The CRUD layer renders the copy and passes it in; the RPC resolves the audience (the submission's approved assignees / the venue's vetters / the author) and inserts rows into `emails` with `sender = null` so a recipient can't read the author's id off the email row. Its per-audience authorization is also what stops an author from bypassing vetting to message reviewers directly. The `resend` consumer brands and delivers these rows like any other.

7. **Server-side fan-out — calls for bids.** A venue's editor or admin writes a short personal note to the volunteers of one biddable role (`queue_call_for_bids`), asking them to come and bid. It is the only mail whose prose a person composes, and the way it stays inside the pipeline's rule is that the note is **one template argument, not a body**: the RPC builds the other five arguments server-side, leaves `subject` and `message` null, and the `resend` function renders `CallForBids` from the registry at send time — which escapes the note and defangs any URL scheme in it. So a caller chooses what one paragraph says and nothing else: not the subject, not the recipients, not a link. That is a stricter contract than `queue_thanks_emails`, which takes a fully pre-rendered subject and body.

   Two differences from `queue_email` are deliberate. It **authorizes against the venue** — `isAdmin(venue) or isPriorityZero(venue)` — where `queue_email` does not check the caller's relationship to a recipient at all. That residual is affordable there precisely because the caller supplies no prose; here they do, so the check cannot be skipped. And it writes **one row per recipient**, never a `cc`: the new-volunteer notice cc's because a welcome should converge into one thread, while these readers are a venue's reviewers, who must not learn each other's addresses — and a biddable role routinely holds more than the 50 addresses Resend accepts on one send. The sender must have a verified contact address, since `reply_to` is resolved to it; the send is refused rather than falling back to `stewards@`, because a personal letter nobody can answer is worse than none.

   `call_for_bids_status` is its read half, behind the same authorization. It answers two things the client cannot: how many volunteers would **actually** receive the message — the same predicate the fan-out uses, so the number the form shows is the number that goes out — and when the venue last asked. The count matters because a client-side count of a role's volunteers would include people the send skips, and the interface would promise more than the feedback banners then report. The last-sent half is there because `emails`' SELECT policy admits venue **admins** only, so a priority-0 editor cannot read their own venue's mail log, and widening that policy would disclose every notice and address at the venue to answer one question. There is deliberately no rate limit — an editor decides when their community needs asking — so this informs that judgment rather than gating it.

**Delivery is recorded, not merely attempted.** `net.http_post` is asynchronous: it returns a handle the instant the request is queued, and the HTTP outcome lands later in `net._http_response`. `send_email()` used to discard that handle, so a missing vault secret, a message Resend refused, and a delivered message were indistinguishable afterwards — and a scholar was told "we sent you a link" in all three cases. `public.emails` now carries `request_id`, `delivery` (`queued` / `sent` / `failed` / `unknown`), `delivery_detail`, and `delivery_at`, for **all** mail rather than verification alone: the trigger is generic, and "which of last week's notices never left the building" is worth being able to ask about any of them. Rows written before the columns existed keep `delivery = null`, meaning "nothing was recorded" — deliberately not backfilled to `'sent'`, which would put a reassuring lie in the one column that exists to be honest. The two paths that never reach pg_net at all (an unset `secret_key`/`supabase_url`, and a `net.http_post` that raises synchronously) now write a terminal `failed` alongside the warning they already raised; delivery stays best effort and still never rolls back the caller's transaction. The state is written by an `UPDATE ... where id = new.id` rather than by assigning to `NEW`, because this is an AFTER trigger — and it stays AFTER deliberately: a BEFORE INSERT trigger runs before the table's CHECK constraints and foreign keys, so moving it earlier to make `NEW` writable would hand the message to Resend and only then discover the row was about to be rejected.

**`reconcile_email_delivery` turns pg_net's answers into verdicts**, on a five-minute `pg_cron` schedule ([20260910010000](supabase/migrations/20260910010000_email_delivery_status.sql)). It runs on a schedule rather than resolving on demand because `net._http_response` is **UNLOGGED** — a restart truncates it — and pg_net garbage-collects it at `pg_net.ttl`, six hours by default. A 24-hour verification link outlives that four times over, and the scholar most likely to ask "did that ever arrive?" is the one who comes back tomorrow, by which time the answer would be gone. Its scan is bounded the way `reconcile_ledger` learned to be: `delivery in ('queued','unknown')` makes `sent` and `failed` terminal, a seven-day floor stops it asking forever about an answer that never came, and a **partial** index on `emails (time_sent) where delivery in ('queued','unknown')` sizes the work to the unresolved set rather than to all mail ever sent. Re-checking `unknown` is what makes it self-correcting, and two runs back to back are a no-op. A request with no response and no answer for fifteen minutes becomes `unknown` rather than `failed`, because the two causes — the worker never ran, or the answer was discarded before the job looked — are genuinely different and neither is knowable from here; claiming the mail failed would be a guess. The status code survives into `delivery_detail`, since the `resend` function answers **502** when Resend refused the message and **400** when it could not render it, and those are different faults with different fixes. Unlike `reconcile_ledger` it emails **nobody**: a steward notification is itself a row in `public.emails`, so if delivery is broken the notice about broken delivery fails too, is marked failed on the next pass, and produces another — a loop driven by a job that runs every five minutes. Signal reaches people through the columns, the Postgres log, and the scholar's own profile. The e2e suite runs without an edge runtime, so every send in it genuinely fails; [global-setup.ts](end2end/global-setup.ts) therefore unschedules this job for the run, or it would truthfully but unhelpfully mark each of them failed mid-suite.

**Links point at the sending environment.** Templates carry an `{origin}` token rather than a hardcoded host. `send_email()` reads the `site_url` vault secret — the same one that builds the verification link — and passes it in the POST body; `resend` resolves the token at render time and gives it to the branded shell for the wordmark link. `site_origin()` (`SECURITY DEFINER`, granted to `service_role` alone) exposes the same value to anything outside the table; the `remind` cron used to need it and no longer does, since its rows are rendered at send time like the rest. Everything falls back to `https://reciprocal.reviews`, so a project that never configures the secret is unchanged.

Venue links are the one deliberate exception to send-time rendering. A template owns the path in its prose (`{origin}/venue/$4/submission/$5`) and takes only the segment as an argument, and that segment is resolved to the venue's web address **at queue time** by the producer — `venuePath`/`venuePathOf` in [SupabaseCRUD](src/lib/data/SupabaseCRUD.svelte.ts), `coalesce(v.slug, v.id::text)` in `public._notify_new_volunteer` and `public.create_volunteer`, and a lookup map in the [remind](supabase/functions/remind/index.ts) cron. Queueing and sending are seconds apart (the `emails` AFTER INSERT trigger), so a rename cannot realistically overtake a message in flight; and if one did, the link still resolves, because the address it was renamed from is gone either way and the id form would have been no better.

The origin is resolved **in the template text, not through the argument path**, and that ordering is load-bearing twice over. Arguments have their URL schemes defanged unless the template declares the position trusted, so an origin arriving as an argument would render as `https[:]//…` and every link would be dead — which is exactly what was happening to `TransactionDeclined` and `TransactionDeclinedVenue`, whose whole link _is_ an argument; both now declare it via `urlArgs`. And the substitution happens before arguments are interpolated, so an argument value that happens to contain the literal `{origin}` stays literal.

**Optional notices.** A template carries `optional: true` to own a preference a scholar can silence, `silencedBy` to defer to another template's, and `defaultOn: false` to ship off and wait to be asked for. A template with none of those is consequential — a charge, a decline, a verification, an assignment, a privilege grant — and is always delivered.

The registry is the source of truth for what can be turned off, but it is TypeScript, and the question "may this scholar be sent this?" has to be answered inside `queue_email` at send time. So two small tables are a **generated copy** of those marks: `public.notification_preferences (key, default_on)` and `public.optional_emails (event, preference)`, produced by [src/email/notificationSeeds.ts](src/email/notificationSeeds.ts) (printed by `node scripts/notification-seeds.js`) and asserted to match by [templates.unit.ts](src/email/templates.unit.ts). A drifted copy would not fail loudly — it would mail people notices they had switched off — so the parity test is the thing keeping it honest, and the marks are pasted into a migration rather than edited by hand.

One predicate reads them: `public.notification_allowed(scholar, event)`, consulted by `queue_email`, `queue_reminder_email`, `queue_thanks_emails` and `_notify_new_volunteer`. That centralization is the substance of the change. The contract used to be that _the producer of an optional email checks that table before queuing_, and exactly one producer ever did — which is the real reason the scholar profile could only ever show one checkbox: marking a second template optional would have rendered a control that silenced nothing. A template with no `optional_emails` row matches nothing and is always sent, so a template accidentally missing from the seed keeps being delivered rather than going quiet, which is the safer way to be wrong about mail. `queue_email` applies the predicate in **both** of its queries, because the second builds the recipient list the caller is told it mailed and the interface renders that as a feedback banner.

`silencedBy` exists because routing the reminders through the registry created duplicate news: a notice, its plural form, and the reminder that chases it are one thing to a reader, and three checkboxes for it would be a worse settings page rather than a more capable one. `defaultOn` exists because "absence of a row means on" was a fine rule for one notice and a bad one for twenty-two — it would have opted every existing scholar into all of them at once. Declaring the default in the registry rather than backfilling rows keeps "adding a preference is one mark on a template" true.

Preferences live in `public.notification_settings (scholar, event, enabled)` rather than on `scholars` for two reasons: scholar metadata is world-readable, so a column there would publish everyone's mute list; and a nullable `venue` column added later gives per-venue muting without a rewrite, which no column can express. Absence of a row still means "no opinion" — it just no longer means "on". There is deliberately **no** column write boundary on that table, unlike `scholars` and `volunteers` — every column is part of "which of my own preferences this is", the row policy pins the only thing that matters, and revoking `scholar`/`event` would break PostgREST's upsert, which compiles to `on conflict do update set` over every column in the payload and is privilege-checked at plan time.

`event` **is** constrained, by a foreign key to `notification_preferences`, and that reverses a decision recorded in the schema file. It was left unconstrained on the reasoning that "an unrecognized key is simply inert, because nothing reads it" — true until `notification_allowed` began reading it. Combined with the missing column boundary above, an unconstrained column would have let any scholar insert `('me', 'SubmissionCharged', false)` and switch off the notice that they had been billed, which DESIGN.md makes an accountability property rather than a preference. The cost is that marking a template optional now needs a migration, which the original comment promised it would not; that promise was worth less than the guarantee.

To add a new email: add a key to the `Emails` map in `templates.ts`, then send it — from application code via `emailScholars(...)`, or (when recipients must be resolved with elevated privileges, as for thank-you notes) via a `SECURITY DEFINER` fan-out RPC. There is deliberately no path that accepts a free-text address, a caller-chosen subject, or a caller-authored body. The one thing a caller may author is a **single bounded argument**, escaped and URL-defanged like every other, inside a template that owns the subject, the framing and the links — which is what the call for bids is, and the limit any future version of it should stay inside. If a new email needs recipients that aren't scholar ids, resolve them inside the RPC from a row the caller already had permission to write; and if it accepts prose, authorize the caller's relationship to those recipients there too, since `queue_email`'s residual is only tolerable for mail nobody wrote.

**Residual, deliberately deferred:** `queue_email` does not yet verify that the caller has a _relationship_ to each recipient, so a scholar can send a real template to a scholar they have no business emailing. That is bounded — no arbitrary prose, no external addresses, no attacker-supplied links — and attributable via `emails.sender`. Per-event authorization is a follow-up.

### Edge function authorization

`orcid` is the third, and it differs from the other two in one way worth stating: it accepts
only scholar ids and iDs the database itself chose, and writes only to a derived cache, so
it would not be an open relay even if the gate failed the way `resend` would. The gate still
applies — an open endpoint that fans out to a third party's API on request is still somebody
else's rate limit to spend.

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

| Category                                                                                                       | Audience                 |                                                                   |
| -------------------------------------------------------------------------------------------------------------- | ------------------------ | ----------------------------------------------------------------- |
| Internal helpers (`_`-prefixed)                                                                                | owner + `service_role`   | steps of an authorized RPC, never entry points                    |
| Trigger functions                                                                                              | owner + `service_role`   | invoked by the trigger, never called directly                     |
| Operational (`reconcile_ledger`, `conservation_violations`, `tokens_as_of`, `replay_audit_log`, `site_origin`) | `service_role`           | run by crons and recovery                                         |
| Ordinary RPCs                                                                                                  | `authenticated`          | each re-implements its own authorization                          |
| `verify_email`, `currency_holder_counts`                                                                       | `anon` + `authenticated` | followed from an email before sign-in; aggregate supply is public |
| **Policy predicates**                                                                                          | `anon` + `authenticated` | **load-bearing — see below**                                      |

The policy predicates stay open on purpose. A policy expression is evaluated as the **querying** role, so that role needs EXECUTE on every function the policy calls, and the `submissions` SELECT policy is granted to `{anon, authenticated}` and calls `isAdmin` and `isPriorityZero`. Revoking those from `anon` breaks anonymous submission viewing outright. They are safe to leave open because each is a read-only predicate about the _caller's_ own relationships (`auth.uid()`, null for anon) over inputs that are publicly readable anyway.

**`supabase db diff` does not compare function ACLs**, so the drift check that guards the rest of this schema is blind here. [supabase/tests/rls/definer_grants.sql](supabase/tests/rls/definer_grants.sql) is the only guard rail: it fails if any definer function outside an explicit allowlist becomes anon-executable, and if any `_`-prefixed helper becomes reachable at all. A new definer function must be added to the migration's lists, and to that allowlist if it is meant to be callable without a session.

### Balance privacy

Balances are private ([#109](https://github.com/reciprocalreviews/reciprocalapp/issues/109), DESIGN.md). The rule is split across two layers for a reason worth keeping:

- The **`tokens` SELECT policy** answers only what a per-row test must — `scholar = auth.uid() or venue is not null`. Two column comparisons, no subqueries, no function calls. A policy is evaluated once per row and this table holds one row per token, so a reserve carrying a community's supply pays for it a quarter of a million times; anything cleverer here would undo the indexing work of `20260830000000`.
- The **audience rule** — minters, venue admins, and accepted active volunteers at a venue on that currency — lives in `public.can_see_balances(currency)` and is asked **once per call** by `public.scholar_balances`, which is `SECURITY DEFINER` and so must carry it. That is what lets the audience be as broad as it is at no per-row cost.

`scholar_balances` filters rather than raising: a caller outside the audience still gets their own row, so a reviewer's submission page does not error merely because they may not see their peers'. The submission page hides the balance column for non-approvers **and** neutralizes `getBalance`, because `sortAssignees`/`sortBids` order ascending by balance — leaving the column out but the ordering in would keep the row order as a balance oracle.

**A predicate helper used in a policy must be declared `STABLE`.** `isAdmin`, `isSteward`, `isMinter`, `isPriorityZero`, `isAssigned`, `isAuthor`, `isConflicted`, `isInApproverChain`, `isRoleApproverVolunteer`, `can_approve_assignment` and `can_claim_editor_role` were all declared `LANGUAGE sql SECURITY DEFINER` with no volatility marker — which means `VOLATILE`, the default. Postgres will not hoist, cache or fold a `VOLATILE` function, so each was re-executed **for every row** the policy was checked against, and several run a query of their own to answer (`isPriorityZero` joins two tables). `isSteward()` shows the cost most plainly because it takes no arguments at all and so has nothing to vary on: as `VOLATILE` the planner still called it once per row — ~57ms over 20,000 rows, against 0.4ms once it is hoisted to a single call. All eleven were marked `STABLE` in [20260830020000](supabase/migrations/20260830020000_stable_rls_helpers.sql); `submission_has_editor` and `venue_submission_editors` already were, so this is the rest of the family catching up rather than a new claim. (`isInApproverChain` and `isRoleApproverVolunteer` were later dropped outright — see the next section — so nine of them remain.) Nothing about their behaviour changes: `STABLE` promises only that a function returns the same answer for the same arguments within one statement, which is what a policy predicate must already do to be coherent.

`STABLE` is necessary but not always sufficient, which `can_see_volunteer` ([20260914010000](supabase/migrations/20260914010000_volunteer_visibility.sql)) is the standing example of. The planner will not inline a function that is `SECURITY DEFINER` **and** carries a `SET` clause — that one is both — and its argument is the row's own id, so there is nothing constant for `STABLE` to fold. Every row costs a real call. The fix is not to weaken the function but to stop reaching it: the policy tests `invited`, `priority` and `volunteer_visibility = 'all'` **inline**, reading `public.roles`, which is world-readable and so discloses nothing, and calls the function only for rows in a restricted role. A venue that has not opted in pays one primary-key lookup instead. When a policy predicate must take a per-row argument, put its cheap cases in the policy and keep the function as the complete rule behind them.

A known cost that this does **not** fix: the `transactions` SELECT policy's minter and venue-admin branches are correlated subqueries against the `currencies.minters` and `venues.admins` **array columns**, keyed on the row's own columns, so they cannot be hoisted and are evaluated per row — `EXPLAIN` on a venue admin's transaction list shows the subplans looping once per candidate row, and the six-way `OR` defeats the partial indexes besides. The root cause is the array columns themselves; making those branches indexable means normalizing `admins`/`minters` into join tables, which touches authorization everywhere and is its own piece of work. In the meantime the paginated lists ask for `{ count: 'exact' }` on the **first page only** — the total is displayed and drives the "load more" stop condition, so it must stay exact, but it was being recomputed on every page, making each "load more" pay for the page twice.

### Submission completion

Submission completion is a guarded action implemented by the `mark_submission_done(submission_id, payment_template, mint_template)` RPC ([supabase/migrations/20260517000000_mark_submission_done.sql](supabase/migrations/20260517000000_mark_submission_done.sql)). It authorizes only priority-0 editors of the submission, validates that every approved non-editor assignment is already completed, and — in one atomic action — compensates every uncompleted priority-0 assignment, flips `submissions.status` to `done`, and stamps `submissions.completed_at`. If the venue cannot cover the total editor payout, it records a single proposed mint sized to the shortfall and returns without changing status; if there are pending non-editor assignments, it returns the blocker list without changing anything.

To enforce this gate, the table-level UPDATE grant is removed from the `authenticated` role and re-granted only on the editable columns — omitting `status` and `completed_at`. (A column-level `REVOKE` alone is a no-op while a table-wide `GRANT ALL` confers UPDATE on every column, so the grant must be narrowed, not merely revoked.) The RPC is `SECURITY DEFINER`, so it is the only path that can write these columns. The result: **done is terminal** — once set there is no API path to revert it, by design.

The same narrowing now also denies DELETE on `venues`, `currencies`, and `submissions` — policy plus a table-level `revoke delete`, matching the `tokens` treatment. Each previously granted deletion to stewards/admins/minters, and each was unreachable: no UI calls them and `CRUD` declares no method for them, so the only way to exercise one was a hand-written PostgREST request. What they permitted was not small. Deleting a venue cascades through its roles to every volunteer, assignment, and compensation row, plus preference levels and thanks; only the money tables' plain (non-cascading) foreign keys stood in the way, which is protection by accident rather than by design. `service_role` keeps its grant, so recovery work at a psql prompt is unaffected.

`volunteers` received the same treatment, and there the dormant path was not merely untidy. A volunteer row is what stops a venue's welcome grant being made twice: `create_volunteer` and `accept_role_invite` size the grant by counting the scholar's existing rows at the role's venue, and `volunteers.active` exists so that unvolunteering keeps the record. DELETE was granted to venue admins and the volunteering scholar and called by nothing — no UI, no `CRUD` method, no RPC — so deleting your own row and volunteering again minted the welcome amount a second time. UPDATE was open the same way for a different reason: the policy authorized the row and said nothing about columns, and its `USING` expression named `scholarid` but never `roleid`, so a scholar could repoint their row to a role at another venue and reset the count without deleting anything. (Reassigning it to another `scholarid` was already refused — Postgres applies a policy's `USING` expression as its `WITH CHECK` when none is given.) The table UPDATE is now revoked and re-granted on `active`, `expertise`, and `papers` only; `accepted` is left out because `accept_role_invite` is what settles the grant, and it is `SECURITY DEFINER`, so the revoke does not reach it.

That policy family gained its **read** boundary in [20260914010000](supabase/migrations/20260914010000_volunteer_visibility.sql), and it is the one place `volunteers` had none: SELECT was `using (true)` for `authenticated` **and** `anon`, so every volunteer at every venue — name, expertise, paper cap, and through the roster page's embed their email and ORCID — was readable by anyone at all. A venue's roster is published at `/venue/<venue>/volunteers`, and that listing is a credential: roles can be accumulated across venues and displayed without anything having been contributed, which is a reward the platform was handing out for signing up. `roles.volunteer_visibility` (`all` | `completed` | `none`, defaulting to `all`, so nothing changes until an admin opts in) lets a venue say who the roster is for.

Four things get past the setting, and the first is load-bearing rather than courteous: **your own record**. The `submissions` SELECT policy and the `assignments` INSERT policy each read `public.volunteers` _inline_, and an inline read in a policy is gated by that table's policy — this one — so without a `scholarid = auth.uid()` branch a restricted role would stop its own volunteers bidding and reading the venue's submissions. [volunteers_rls.sql](supabase/tests/rls/volunteers_rls.sql) asserts both, and both fail if the branch is removed. The other three are **invite-only roles** and the **priority-0 role**, each status nobody can award themselves, and **whoever staffs the role**. Exempting priority 0 also repairs something quieter: `emailEditorsOf` resolves the editor mailing list by reading this table with the **caller's** session, discards the error, and treats an empty read as nobody to mail — and its callers include authors, bidders and reviewers. Moving that fan-out server-side, the way `queue_call_for_bids` already resolves its recipients, is the better fix and is not done here.

The predicate is **`can_see_volunteer(_volunteer uuid)`**, keyed on the row id rather than the `(roleid, scholarid)` pair it reads like it wants, and that is a security property rather than a style choice. It is granted to `anon` because a policy expression is evaluated as the querying role; `public.scholars` is world-readable; and under the `completed` tier the pair form would answer, for any scholar id an anonymous caller cared to try, whether that scholar has finished work at the venue — reconstructing exactly the reviewing activity `token_events` and `tokens_as_of` are kept from `anon` to protect. Keyed on the row id, the answer concerns a row whose id the caller already holds, and holding it they could have selected the row instead. The `completed` tier joins `assignments` through `roles` rather than reading `assignments.venue`: both columns carry a foreign key, but `venue` is a denormalized copy the client supplies and nothing constrains it to agree with the venue of `assignments.role`.

Hiding a roster must not hide its **size**. The role card badge, the venue's dashboard tile and the roster page's headings all counted the rows they had, which under a filtering policy means every reader is shown a different number and a venue loses the recruiting signal along with the names. **`venue_volunteer_counts(venue)`** answers the count and nothing else — no name, no membership — which is the `submission_has_editor` and `currency_holder_counts` shape, and is why both new functions are allowlisted in [definer_grants.sql](supabase/tests/rls/definer_grants.sql).

The same pattern makes `transactions` an immutable record, on both sides of a row's life. The table-level UPDATE is revoked and re-granted only on `status`, `tokens`, and the decline fields, locking the identity columns. INSERT is narrowed the same way — re-granted only on the columns a caller may legitimately supply, omitting `id`, `created_at`, and `seq` — so a client can propose a transaction but cannot choose its identity, backdate it, or pick its place in the order. DELETE is denied outright: the policy named `"transactions cannot be deleted"` previously had a `USING` clause that in fact _granted_ deletion to any minter of the currency, so a minter could erase approved transfer history while the tokens those rows described stayed put, leaving tokens with no account of how they got where they are.

Column grants cannot express a rule that depends on the row's _current_ state, and two such rules matter, so a `BEFORE UPDATE` trigger carries them ([20260808030000](supabase/migrations/20260808030000_transactions_immutable.sql), error code `RR005`):

- **A decision is final.** `status`, `tokens`, `decliner` and `decline_reason` are writable because a proposed transaction has to become approved or declined — and nothing stopped that happening twice. An approved transfer, tokens already moved and recorded in `token_events`, could be flipped to `declined` afterwards, leaving the ledger saying value moved and the transaction saying it was refused.
- **The amount cannot be resized.** There is no amount column; the amount _is_ `cardinality(tokens)`. Since `tokens` is writable, the amount was writable: a proposed row carrying N placeholders could be approved with a different number of real ids. Every legitimate path already preserved the count — `approve_transaction` sizes its work from `cardinality(_txn.tokens)` — so this makes a habit into a rule. Filling placeholders in at the same count remains allowed, since that is what approval is.

A trigger rather than a policy or a grant, because those decide by _who_ is asking while this decides by what the row already is, and it must bind the `SECURITY DEFINER` RPCs and anyone at a psql prompt equally. A restore is unaffected: data loads under `session_replication_role = replica`, so historical rows are not judged against rules they predate.

`seq` is a `bigint` from a sequence, and it is what makes the order of history well-defined. `created_at` defaults to `now()`, which is transaction _start_ time, so every row a single RPC writes carries an identical timestamp — `create_submission` inserts one charge per author that way. Sorting on `created_at` alone therefore leaves ties the planner may break differently per query, and a `LIMIT`/`OFFSET` over an unstable sort can return one row on two pages while skipping another; the three paginated transaction lists all sort `created_at desc, seq desc` for this reason. Note that a sequence gives _insertion_ order rather than _commit_ order, so anything treating `seq` as a replication watermark should compare against `pg_snapshot_xmin(pg_current_snapshot())` instead of assuming `max(seq)` is final.

Per-editor compensation amounts come from `compensation(role, submission_type)`; multi-editor submissions are supported and all priority-0 editor assignments are paid in the same transaction. The RPC returns a structured JSONB result (`completed | blocked | insufficient`) that the application layer narrows with a runtime type guard before dispatching `WorkCompensated` emails (per-recipient, surfaced as notification banners via the `handle()` feedback channel, and collapsed into one banner when there are more than a few — see Data access).

### One rule: approving an assignment

**`can_approve_assignment(submission, role)`** ([20260816010000](supabase/migrations/20260816010000_can_approve_assignment.sql)) is the approval rule, and since [20260913000000](supabase/migrations/20260913000000_approver_is_submission_scoped.sql) it is the only one: a venue admin, or the holder of an **approved assignment on this submission** for either the venue's priority-0 role or the role that approves the one in question. `complete_assignment` calls it, as do the `assignments` SELECT, UPDATE and INSERT policies and — by its absence, see below — the `submissions` SELECT policy. [src/lib/data/canApproveAssignment.ts](src/lib/data/canApproveAssignment.ts) is the UI-gating mirror; the two are pinned to the same table of cases by [canApproveAssignment.unit.ts](src/lib/data/canApproveAssignment.unit.ts) and by the `create_submission`/`complete_assignment` cases in [atomic_crud_rpc.sql](supabase/tests/rpc/atomic_crud_rpc.sql).

It used to have two rivals. **`isRoleApproverVolunteer(role)`** (formerly `isApprover`) asked something else entirely — is the caller an **accepted volunteer** on the role that approves this one, _anywhere in the venue_? — and **`isInApproverChain(role)`** asked the same question recursively, walking `roles.approver` upward. Both read `volunteers`, took no submission, and had no admin or priority-0 branch. Between them they were the `USING` clause of the `assignments` SELECT and UPDATE policies, the `WITH CHECK` of its INSERT policy, and one branch of the `submissions` SELECT policy.

Both of those, along with `isPriorityZero`, `mark_submission_done` and the submissions author-list lock, key on **priority 0**. `roles.priority` therefore carries authority, not just presentation, and the invariant that makes it meaningful is that a venue has exactly one role at priority 0. Nothing used to establish that invariant: the column defaults to `0` and roles were created with a plain insert, so every role a venue admin added arrived at priority 0 and silently made its accepted volunteers editors — visible in the UI only as several role cards each claiming to be the venue's highest priority. **`create_role(venue, name, description)`** ([20260828030000](supabase/migrations/20260828030000_role_priority.sql)) is what establishes it: it takes an advisory lock on the venue and inserts at `max(priority) + 1`, so a venue's first role — the Editor that proposal approval creates — still lands at 0 and every later one goes to the bottom. Unusually among the RPCs here it is `security invoker` rather than `security definer`, precisely because it needs no authorization logic of its own: the existing "only admins can create venue roles" policy applies to the insert unchanged, which [create_role_rpc.sql](supabase/tests/rpc/create_role_rpc.sql) asserts by checking that a non-admin caller still gets 42501. The same migration renumbers venues that already had ties. Reordering remains the admin-facing way to move that authority, via the ↑/↓ controls that renumber the venue densely.

Unifying them was a permissions change rather than a refactor, and this file used to argue against it: narrowing the venue-wide rule, it said, "would silently revoke UPDATE from every AE approving a bid, breaking bidding." That was wrong, and the mistake is worth keeping on the record because it is the assumption that produced the bug. An AE approving a bid is an AE **seated on that submission**, and `can_approve_assignment` admits exactly that person; the case the old reasoning was protecting — an approver acting on a submission they hold no assignment on — is one the UI never offered, because `canApproveAssignment` has always been submission-scoped. What the venue-wide rule actually bought was reach: at a venue whose Reviewer role is approved by an Associate Editor role, `isRoleApproverVolunteer(Reviewer)` is unconditionally true for **every** accepted AE volunteer, on every submission. So one branch of the `submissions` SELECT policy exposed any submission carrying a reviewer assignment to all of them, the `assignments` policies exposed those reviewers' identities at a venue running anonymous review, and the UPDATE policy let any of them approve or unassign reviewers on papers they had no role on — writes the UI hid and the database allowed.

[20260913000000](supabase/migrations/20260913000000_approver_is_submission_scoped.sql) therefore points all four policies at `can_approve_assignment` and drops both venue-wide helpers, so the superseded rule cannot be reached for again. The `submissions` SELECT branch is dropped rather than rewritten: every case `can_approve_assignment` would admit is already covered by that policy's `isAdmin` and approved-assignment branches. Read access narrows for nobody who could act. Write access narrows deliberately in two places (approving on a submission you are not seated on; seating someone where you hold only a subordinate role) and **widens** in one — a submission's editor may now seat and approve any role on it without also volunteering in the approving role, which is what the priority-0 branch of `can_approve_assignment` already said they could do. The regression cases live in [submissions_rls.sql](supabase/tests/rls/submissions_rls.sql) and [assignments_rls.sql](supabase/tests/rls/assignments_rls.sql); each fails against the old policies.

The venue-wide test returns in exactly **one** place, and deliberately: the `volunteers` SELECT policy ([20260914010000](supabase/migrations/20260914010000_volunteer_visibility.sql)) admits the holder of a role's `approver`, venue-wide, to that role's roster. It is the same predicate `isRoleApproverVolunteer` was, and it is not the same grant. What was removed was the authority to **act** — to see a submission, approve an assignment on it, or seat someone — on papers the approver held no role on. What is restored is a **read of who is available**, granting nothing over any submission, and it has to exist because an approver who cannot see the pool cannot pick anyone out of it. Do not read it as the venue-wide rule coming back.

A third near-copy, in `SupabaseCRUD.requestCompensation`, picked email recipients by a rule that omitted the priority-0 editor branch and treated admins as a fallback rather than a first-class branch, so the two people most able to act on a compensation request were often the two who never heard about it; it now uses the same three-branch union.

### Resubmission links and per-type cost

A submission records its predecessor two ways: `submissions.previous` is an internal foreign key (`on delete set null`) to another submission, preferred wherever the chain is displayed; `submissions.previousid` is the legacy free-text external manuscript ID, retained for predecessors not on the platform (and matched against `externalid` within the same venue only as a fallback). Individual submissions set `previous` from a dropdown of the author's own prior submissions in the venue — choosing one mirrors its external ID into the (then read-only) `previousid` field **and auto-selects the matching revision submission type** (the `submission_types` row whose `revision_of` points at the predecessor's type). A typed external ID that matches one of the author's priors does the same best-effort. `bulk_import_submissions` best-effort resolves each row's `previousid` to an on-platform `previous` (exact `externalid` match within the venue).

Submission cost is **per submission type**: `submission_types.submission_cost` (`not null default 0`); there is no venue-wide submission cost. Each type is a different amount of work, so a resubmission — being its own revision type — simply carries its own cost; no separate resubmission cost exists. Admins edit a type's cost in the submission types table on the venue dashboard. The new-submission form charges the selected type's cost, and the bulk-import RPC sizes the mint by summing each **written** row's submission type cost — a row skipped because the venue already has that external ID funds nothing.

`create_submission` enforces that the author charges add up to that cost (`RR007`) and that no author is listed twice (`RR008`) ([20260816000000](supabase/migrations/20260816000000_submission_cost_and_authors.sql)). Both rules previously lived only in the new-submission form, so they held for callers who came through the form and for no one else — anything reaching the RPC directly could name its own price, and a duplicated author was charged twice for one manuscript because the RPC's loop indexes the authors array positionally. Neither can be a `CHECK` constraint: the cost rule spans two tables, and the duplicate rule must not apply to bulk-imported submissions, which arrive by a different path with no payments. The same call also verifies that the submission type belongs to the venue being submitted to, which was never checked. `src/lib/data/charges.ts` is the client half, so the form can refuse before the round trip rather than instead of it.

`RR009` completes the set ([20260817010000](supabase/migrations/20260817010000_create_submission_author_check.sql)): the caller must be one of `_authors`, or an admin of the venue (which is how DESIGN's "submissions can be added manually by editors" works). The RPC previously required only that _someone_ was signed in, and self-service ORCID sign-up makes that a low bar — so any account could create a submission at any venue and leave proposed charges sitting against scholars who had never heard of it, each of which the charged scholar then sees on their dashboard and now receives mail about. The form's `isNonAuthor` guard remains, but it was never a control: it only evaluates once an ORCID lookup has resolved, and nothing obliges a caller to use the form. It now exempts venue admins too, so it admits exactly what the RPC does ([#153](https://github.com/reciprocalreviews/reciprocalapp/issues/153)); before that the form was stricter than the database on the one path the manual add exists for, and an editor filling it in for someone else got no balance check and no submit button. For the same reason the form no longer pre-fills an admin as the first author — the prefill's premise is that a non-author's submission is refused anyway, which is what stops being true for them, and an unnoticed prefill would record the editor as a co-author of a paper they did not write.

## Locales

Localization is type-driven so the schema cannot drift from the strings:

1. [src/lib/locales/Locale.ts](src/lib/locales/Locale.ts) defines a single `LocaleText` interface — the source of truth for every user-visible string.
2. `npm run locale-schema` runs `ts-json-schema-generator` to emit [src/lib/locales/LocaleText.json](src/lib/locales/LocaleText.json).
3. `npm run locale-validate` runs `ajv` against the per-language JSON files.
4. `npm run locale` does both. Run after any change to `Locale.ts`.

The English locale file lives at [static/locales/en.json](static/locales/en.json). The root [+layout.ts](src/routes/+layout.ts) imports it through the `$locales` alias — a plain static import, so it is part of the bundle on both sides — and exposes it via `setLocaleContext()`. Components consume strings through [src/lib/locales/Text.svelte](src/lib/locales/Text.svelte) and locale-typed prop functions:

```svelte
<Text path={(l) => l.page.login.buttons.login} />
<TextField label={(l) => l.page.login.form.email.label} />
```

It stays in `static/` because `locale-validate` globs `static/locales/*.json`, and it is still served there for anything that wants a locale over HTTP — but nothing in the app fetches it any more. It used to: the root `+layout.server.ts` did `await fetch('/locales/en.json')` and returned the parsed object as load data. Both halves of that were expensive. A server load has no filesystem read for `static/` under adapter-vercel, so kit's `fetch` fell through to a real outbound HTTPS request from the function back to its own origin — 90KB fetched and parsed on every render of every non-prerendered page. And because it was _server_ load data, SvelteKit serialized all 90KB into every HTML response, and into every `__data.json` that `invalidateAll()` refetches after every write. Importing it in the universal load fixes both: universal-load return values are never serialized (which is already why the `db` instance can be returned), and in the browser it arrives inside a content-hashed chunk cached for a year.

Keep it a **static** import. A dynamic `import()` is not in the root layout's static graph, so SvelteKit emits no `modulepreload` for it, and hydration awaits every universal load before mounting — it would trade an HTML payload for a serial round trip. A second language becomes a branch in `+layout.ts`, still statically imported.

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
- `getFeedback()` / `addFeedback()` — global error/success notification stack. Unlike its neighbours this is **not** a context: `src/routes/feedback.svelte.ts` holds the stack in module-level `$state`, so there is no `setFeedback()` to pair with it.
- `setAuth()` / `getAuth()` — authenticated session and scholar

The chrome uses no context channel of its own. Breadcrumbs travel in load data — any
`+page.ts` or `+layout.ts` may return `breadcrumbs`, built with the helpers in
[breadcrumbs.ts](src/lib/data/breadcrumbs.ts) — and the root layout reads them off
`page.data`. The page's title band is rendered in flow by
[Page.svelte](src/lib/components/Page.svelte), which pins it below the nav using the
`--nav-height` that [measure.ts](src/lib/components/measure.ts) observes.

Both were once mutable contexts that `Page` wrote from an `$effect`, and that is worth
remembering before reaching for the pattern again: an `$effect` does not run during SSR,
and the layout renders `<Nav>` before its children, so a title handed upward could not
appear in the server HTML at all. It arrived at hydration and pushed the page down on
every load, and collapsed and regrew on every client-side navigation.

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

`Button` carries one invariant worth stating: a button whose locale entry has a `warn` string confirms before it acts, replacing itself with a cancel/confirm pair that only commits on the second click. For the duration of an `action` that returns a promise, the primary button and both halves of the confirm pair are disabled and `act()` refuses re-entry — so the least reversible actions in the platform commit exactly once per confirmation, however many times the button is pressed. Call sites therefore do not need their own in-flight flag; `active` is for validity, not for busy-ness. Add a local flag only to change a button's label while it works (as `EditableText` does) or to gate other controls alongside it.

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

`orcid_profiles` is deliberately **not** audited — see ORCID profile mirror above for why a
derived table whose claim stamp changes on every refresh is the wrong thing to copy whole
rows of into the most sensitive table in the schema.

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

Conservation is also callable on its own, as [`public.conservation_violations(_currency)`](supabase/schemas/reconciliations.sql). Two reasons. It **reads**, where `reconcile_ledger()` writes a `reconciliations` row and mails the stewards — so the obvious way to look at a failing economy used to make the record of it worse and send another email to the people already reading the first. And it takes a currency, which is what lets the invariant be tested at all: `seed.sql` creates tokens with direct INSERTs, so every development and CI database permanently has `unattributed_mints > 0` and check 6 **skips**. The check was real, the alarm was wired, and until [supabase/tests/invariants/conservation.sql](supabase/tests/invariants/conservation.sql) nothing had ever executed the query outside production.

**The 2026-08-30 incident.** Two `ReconciliationFailed` emails arrived that day, at 03:45 and 22:15 UTC, each reporting `conservation violations: 1` and nothing else. They were **one** violation seen twice: `_since` bounds checks 2, 3 and 5 and never check 6, so the Sunday unbounded run and the nightly bounded one compute conservation identically. Worth knowing before treating a second email as an escalation. That the count was a _number_ rather than the string `skipped` was itself the evidence that narrowed it — check 6 runs only when `unattributed_moves` and `unattributed_mints` are both 0, so every token in production was created and moved under an attributed transaction, and with replay, chain, dangling and placeholder checks all clean, nothing had escaped the trigger or been altered by hand. What was left was precise: tokens **created** inside an operation that recorded only a **movement**. The cause was the two shortfall-mint paths described above. The check caught a defect nothing else could, and it caught it precisely _because_ the attribution code was correct enough to let it run.

### Scheduled jobs

The ORCID mirror deliberately adds **no** job here. Refreshing is driven by reads — a page
that renders a scholar asks for a refresh afterwards, and the claim's cooldown bounds how
often that can reach ORCID — plus `backfill_orcid_profiles` for the initial population,
which a steward runs and re-runs until it returns 0. A sweep would burn the daily budget on
accounts nobody is looking at, and would be one more thing a restored database could fire at
the outside world.

Four `pg_cron` jobs now run: `remind-daily` at 22:00 UTC, `reconcile-ledger` at 22:15, `reconcile-ledger-full` weekly, and `reconcile-email-delivery` every five minutes at :03 past — staggered so they never contend. Both live in `cron.job`, which is **cluster state outside every schema dump** — captured separately by [dump.sh](supabase/dr/dump.sh) into `cron.json` and by `quarantine.sql` before a restore. That is not theoretical: `remind-daily` was silently lost once by a `supabase db diff` run (see `supabase/migrations/20260517230819_restore_remind_cron.sql`).

## Data rights

`export_scholar_data` includes the ORCID mirror, and `forget_scholar` deletes it. The delete
is explicit and has to be: the foreign key is `on delete cascade`, but erasure **anonymises
the scholar row in place rather than deleting it**, so no cascade ever fires — the same
reason `email_verifications` is deleted by hand there. Two guards stop a refresh claimed
moments earlier from writing the row back afterwards: `claim_orcid_refresh` skips a scholar
with a null iD, and the edge function re-reads `scholars.orcid` before writing and skips one
whose iD has changed or gone.

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

The first drill found something worth knowing: **a bare Postgres database is not a valid restore target.** Restoring into one succeeded, matched every row count, and silently produced a database with 29 of 71 RLS policies missing, because every policy calls `auth.uid()` and the `auth` schema did not exist. Row counts alone would have called that a success. `drill.sh` now refuses such a target up front. The operational consequence is in [RECOVERY.md](RECOVERY.md); the architectural one is that this schema is not portable to plain Postgres — it depends on Supabase's `auth` schema at the policy level, not merely at the application level. It depends on that schema structurally too: `on_auth_user_created` is a trigger on `auth.users` running a `public` function, so no schema-scoped dump carries it, and a restore without it leaves every subsequent sign-up with no `scholars` row. [dump.sh](supabase/dr/dump.sh) captures such triggers explicitly for that reason.

Point-in-time recovery is **not** enabled. Instead the append-only logs do the same job for a fraction of the cost, which is what they were built for: [tail.sh](supabase/dr/tail.sh) exports `audit_log` and `token_events` hourly — a few kilobytes, because they are the only tables a restore needs to catch up on — and [replay.sql](supabase/dr/replay.sql) applies them over a restored dump via `replay_audit_log()`. That takes the recovery point from **24 hours to roughly one**, and it is demonstrated rather than assumed: restoring a nightly dump alone loses the changes made after it, and replaying the tail brings them back to exactly the prior state.

One ordering rule matters enough to state here. **Replay must happen before anything else writes, including before re-arming.** `seq` is an identity column, so after a restore it resumes from the restored maximum and any intervening write takes the very numbers the tail is carrying; deduplicating on `seq` would then discard the tail's real rows as duplicates. `rearm.sql`'s reminder stamping is enough to trigger this, and did on the first test — the replay reported success having applied the wrong rows. `replay.sql` now refuses to run when `audit_log` has moved past the watermark.

## Testing

`orcidProfile.ts` and `orcidProfileView.ts` are on the extracted-pure-logic list, which is
what that list is for: the first parses ORCID's nested JSON against committed fixtures
captured once from the live API, and the second owns the line-joining and the
`hasAnything` predicate that decides whether a section renders at all. Neither touches the
network. `supabase/tests/rls/orcid_profiles_rls.sql` proves the table is unwritable by every
client role including the scholar's own, `rpc/orcid_refresh_rpc.sql` covers the claim and
the cooldown, and `invariants/erasure.sql` covers the delete that no cascade would perform.

- **Unit.** Vitest, node environment, no DOM. Files matching `src/**/*.unit.ts`, co-located with the module under test. Run with `npm run test:unit`.

  There is no component-testing setup, and the unit layer is not the place to re-test what the pgTAP suites and Playwright already cover. Its job is the pure logic in between — which means logic has to be **reachable** to be tested, and most of the interesting rules used to live inside `.svelte` files where nothing could import them. So the sort/filter and validation rules are extracted into plain modules that the components then import: [sortSubmissions.ts](src/lib/data/sortSubmissions.ts) (search matching, the author-visibility gate, payment status, the sort pipeline), [sortAssignees.ts](src/lib/data/sortAssignees.ts) (assignee and bid ordering), [charges.ts](src/lib/data/charges.ts), [bulkImportRows.ts](src/lib/data/bulkImportRows.ts), [columnMapping.ts](src/lib/data/columnMapping.ts) (matching a CSV's own headers to the importer's fields), [matchPersonName.ts](src/lib/data/matchPersonName.ts) (resolving a written name to one of a venue's volunteers), [volunteersView.ts](src/lib/data/volunteersView.ts) (the volunteers list's search, how its expertise keywords are ranked, and the order its rows appear in), [toCSV.ts](src/lib/data/toCSV.ts), [canViewSubmission.ts](src/lib/data/canViewSubmission.ts), [inviteList.ts](src/lib/data/inviteList.ts) (what a comma-separated list of addresses, ORCID iDs, and names currently matches, which entries are still waiting on an answer, and which entry a chosen scholar came from), [postgrestFilter.ts](src/lib/data/postgrestFilter.ts) (quoting a value into a filter built as a string), and [interpolate.ts](src/lib/locales/interpolate.ts) — the last being the single substitution pass every user-visible string goes through. Each takes its page's reactive reads as an explicit context argument (including `now`, so time-dependent rules are deterministic) rather than closing over them. When adding logic to a component that has a rule in it — an ordering, a permission, an arithmetic — put the rule in a module and let the component call it.

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
