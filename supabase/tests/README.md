# RLS test suite (pgTAP)

Adversarial Row-Level-Security tests for every table, operation, and scholar
privilege (issue #79). RLS is the only access gate in this database (every table
is `grant all` to `anon`/`authenticated`/`service_role`), so these tests are the
guard rail for the entire authorization model.

## Running

```bash
npm run start      # ensure the local Supabase stack is up (or: supabase start)
npm run test:rls   # supabase test db — runs pg_prove over supabase/tests/**/*.sql
```

`supabase test db` runs against the **already-running** local database and does
not reset it. Every test wraps its work in `begin … rollback`, so the suite is
hermetic and can be re-run without `npm run reset` in between. CI runs it via
[`.github/workflows/rls.yml`](../../.github/workflows/rls.yml), which the
staging/production deploy workflows gate `migrate` on.

To iterate on a single table while authoring, run the whole suite (the `\ir`
include of the shared helpers is only mounted when the entire `tests/` tree is
passed, so `supabase test db <one-file>` will not find it).

## Layout

- `_helpers/helpers.sql.inc` — shared helpers, pulled into each test with
  `\ir ../_helpers/helpers.sql.inc`. Deliberately **not** `*.sql` so pg_prove
  does not run it as a (planless) test. Provides:
  - **Auth context:** `tests.authenticate_as(uuid)`, `tests.authenticate_as_anon()`,
    `tests.clear_authentication()` (back to the owner/`postgres` context for
    fixture setup). These switch the local role + `request.jwt.claims.sub`,
    mirroring how the end2end tests probe RLS.
  - **Fixture builders** (run in owner context, return the new id):
    `create_scholar`, `create_currency`, `create_venue`, `create_role`,
    `create_volunteer`, `create_submission_type`, `create_submission`,
    `create_assignment`. Tables without a builder are inserted directly.
- `rls/<table>_rls.sql` — one file per table.

## Conventions

Each file: `\ir` the helpers → `begin` → `create extension if not exists pgtap`
→ `select plan(N)` → assertions → `select * from finish()` → `rollback`.

- Create all fixtures **before** the first `authenticate_as` (or after
  `clear_authentication`) — fixture inserts must bypass RLS and write `auth.users`.
- Each table asserts its full policy set once with `policies_are(...)`.
- Assertion discipline (picking the wrong one silently passes):
  - SELECT allowed/denied → `isnt_empty` / `is_empty`.
  - INSERT denial, a `with check` violation, or writing a column the role lacks
    privilege on → `throws_ok(sql, '42501', …)`.
  - UPDATE/DELETE blocked only by a `using` clause → **0 rows, no error**; assert
    the row is unchanged (`is(...)` / `is(count, 1)`).
  - Allowed write → `lives_ok`.

## Coverage matrix

One file per table; each covers every operation that has a policy, with a
positive and an adversarial-negative case per privilege branch.

| Table | SELECT | INSERT | UPDATE | DELETE | Notable adversarial cases |
|-------|:------:|:------:|:------:|:------:|---------------------------|
| scholars | ✓ | ✓ | ✓ | ✓ | insert blocked for all; update self vs steward |
| venues | ✓ | ✓ | ✓ | ✓ | steward vs admin; no_minter_admins trigger |
| currencies | ✓ | ✓ | ✓ | ✓ | steward-only insert; minter-only mutate; no_admin_minters |
| exchanges | ✓ | ✓ | ✓ | ✓ | minter of either currency |
| roles | ✓ | ✓ | ✓ | ✓ | admin-only |
| volunteers | ✓ | ✓ | ✓ | ✓ | self vs admin; invite-only roles |
| proposals | ✓ | ✓ | ✓ | ✓ | steward-only mutate |
| supporters | ✓ | ✓ | ✓ | ✓ | self-only update/delete |
| tokens | ✓ | ✓ | ✓ | ✓ | anon cannot read; minter cannot move ownership; no delete |
| submission_types | ✓ | ✓ | ✓ | ✓ | admin-only |
| compensation | ✓ | ✓ | ✓ | ✓ | anon cannot read; admin-via-role's-venue |
| preference_levels | ✓ | ✓ | ✓ | ✓ | anon cannot read; admin-only |
| submissions | ✓ | ✓ | ✓ | ✓ | author/bidder/assignee visibility; status immutable; author-list lock |
| assignments | ✓ | ✓ | ✓ | ✓ | approver-chain + admin minus conflicted; bidder insert |
| conflicts | ✓ | ✓ | ✓ | ✓ | admin/volunteer insert; admin-only mutate |
| emails | ✓ | ✓ | ✓ | ✓ | sender/recipient/admin only; update & delete blocked |
| transactions | ✓ | ✓ | ✓ | ✓ | no-self-enrichment; immutable except status/tokens; minter-only delete |
