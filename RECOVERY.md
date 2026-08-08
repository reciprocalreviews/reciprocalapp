# Recovery

How Reciprocal Reviews' data is backed up, and how to get it back.

The token economy is not a cache. A scholar's balance is reviewing labor they
actually performed, and there is no upstream system it can be re-derived from —
if it's gone, it's gone. This document is what stands between an incident and
that outcome.

> **Status.** The nightly off-platform backup is in place, and the restore
> procedure below is written and its scripts tested — `quarantine.sql` and
> `rearm.sql` have been exercised against a live database and verified to
> neutralize and restore every control they touch. A backup has now been
> **restored end to end and verified against its manifest** — see
> [Drills](#drills) for the measured time and, importantly, what that number does
> and does not cover. What has **not** happened yet is a rehearsal against a
> *hosted* project, which is where provisioning, the vault, and edge function
> deploys get exercised. See [Scenarios](#scenarios) for which situations need a
> restore at all — several do not.

---

## What you can currently recover from

| | Covers | Recovery point |
|---|---|---|
| **Nightly encrypted dump** (this repo) | Project loss, account loss, bad migration, logical corruption, malicious deletion | up to **24h** on its own |
| **Hourly tail + replay** | Everything above, with far less loss | **~1h** |
| **Supabase's own backups** | Infrastructure failure | plan-dependent; see below |

**Point-in-time recovery is not enabled.** Supabase offers PITR as a paid add-on
(~$100/mo/project) giving roughly 2-minute granularity. Instead, the append-only
logs do the same job more cheaply: [tail.sh](supabase/dr/tail.sh) exports
`audit_log` and `token_events` every hour — a few kilobytes, since they are the
only tables that change in a way a restore needs — and
[replay.sql](supabase/dr/replay.sql) applies them over a restored dump. That is
the whole reason the ledger exists, and it brings the recovery point from 24
hours to about one.

Demonstrated rather than assumed: restoring a nightly dump alone loses the
changes made after it, and replaying the tail brings them back to exactly the
state before the failure.

**Check what your Supabase plan actually provides**, because it is currently an
unexamined assumption:

- **Free** — no meaningful recoverable backup. Everything below is your *only*
  recovery.
- **Pro** — daily physical backups, 7-day retention, restored through Supabase
  support. Not drillable on demand.
- **PITR add-on** — the only thing that answers "bad migration at 14:03, noticed
  at 14:20" without losing the rest of the day.

Supabase's backups and this repo's backups are not redundant with each other.
Theirs restore faster; ours are the ones that survive losing the account, can be
rehearsed whenever you like, and are the only copy you hold the keys to.

---

## What a backup contains

`supabase/dr/dump.sh` writes six artifacts, each encrypted separately:

| Artifact | Why |
|---|---|
| `public.dump` | Application schema **and** data, custom format (so a restore can be surgical: `pg_restore -t submissions`) |
| `auth.dump` | `auth.users` + `auth.identities`, data only |
| `roles.sql` | Cluster roles via `pg_dumpall --globals-only --no-role-passwords` |
| `extensions.sql` | `create extension` DDL. **Not carried by `pg_dump`** — extensions are cluster state, not schema state |
| *(privileges)* | Carried inside `public.dump`. `--no-privileges` is deliberately **not** used — see below |
| `cron.json` | The `cron.job` table |
| *(hourly)* `token_events.csv`, `audit_log.csv`, `auth_users.csv`, `auth_identities.csv`, `tail.json` | Written by [tail.sh](supabase/dr/tail.sh) every hour to `<target>/tail/<date>/<time>Z/`, and applied by [replay.sh](supabase/dr/replay.sh). `emails` is deliberately absent: re-inserting its rows would re-send them |
| `manifest.json` | Row counts, watermarks, migration list, extensions, realtime table list, RLS policy count, vault secret *names*, and a SHA-256 of every other artifact |
| *(vault secret names live in the manifest)* | So a restore knows which secrets must be re-entered by hand |

Three of these exist because of things that are easy to get wrong:

- **`auth.dump` is not optional.** `public.scholars.id` references
  `auth.users(id) ON DELETE CASCADE`. A `public`-only dump restores into a
  project with zero scholars and dangling everything else. This is why the script
  uses `pg_dump` rather than `supabase db dump`, which is scoped to the schemas
  it knows about.
- **`cron.json` is captured separately** because `cron.job` lives outside every
  schema dump. That is exactly how the `remind-daily` job was silently lost once
  before — see `supabase/migrations/20260517230819_restore_remind_cron.sql`.
- **`extensions.sql` exists because a rehearsal lost `pg_net`.** It was created
  without a schema override, so on that project it lived in `public` and
  `drop schema public cascade` took it; nothing in the dump brought it back.
  `send_email()` then called a `net.http_post` that no longer existed — the row
  recorded, delivery best-effort, **not one email leaving**. That is the same
  failure mode migration `20260720020000` was written to fix, found again from the
  other direction. `drill.sh` now applies this file and asserts every recorded
  extension.
- **Vault *values* are deliberately never captured.** They are set by hand on
  hosted projects and belong in a password manager, not in an artifact CI can
  write. The manifest records the *names* so a restore knows what is missing.

### The manifest is what makes a drill an assertion

Without it, "the restore finished" is a feeling. With it, you can check exact row
counts per table, `auth.users` against `scholars`, the applied migration list,
the RLS policy count, and the realtime publication membership. A restore that
doesn't match the manifest is a failed restore, and you find out during the
drill instead of during the incident.

---

## Provisioning

**Step-by-step instructions are in
[supabase/dr/PROVISIONING.md](supabase/dr/PROVISIONING.md)** — follow that to set
this up, or to rebuild it if the storage account is ever lost. What follows is
the summary of what exists and why.

Four things to set up once. Until all four exist, the nightly job fails on its
first step with a message naming what's missing.

### 1. The age keypair

Backups are encrypted with [age](https://github.com/FiloSottile/age) in
**public-key mode**, which buys one specific property: **CI can write backups but
cannot read any backup, including the one it just made.** A compromised
`GITHUB_TOKEN` or a malicious workflow gets you nothing.

On a trusted machine — **never in CI**, since the private half existing there
would defeat the entire arrangement:

```sh
age-keygen -o backup-identity.txt
grep 'public key' backup-identity.txt
```

- Commit **only** the public key to `supabase/dr/backup-recipient.age.pub`.
- Put `backup-identity.txt` in a password manager **and** somewhere offline.

> **If you lose the private key, every backup you hold becomes permanently
> unreadable.** There is no recovery path. Store it in two places before you
> enable the nightly job.

### 2. The bucket

Cloudflare R2 is the assumed target: S3-compatible, and free egress matters
because drills pull whole dumps.

1. Create a bucket, e.g. `reciprocal-backups`.
2. Add lifecycle rules for the grandfather-father-son tiers the workflow writes:
   `daily/` expire after 14 days, `weekly/` after 8 weeks, `monthly/` after 24
   months.
3. **Add prefix-scoped bucket lock rules** — 14 days on `production/daily/`, 56
   days on `production/weekly/`. This is what survives a compromised CI
   credential or a malicious insider; without it the backup credential is a
   single point of failure *for the backups themselves*. R2's feature is *bucket
   locks*, not S3 Object Lock: prefix-scoped, added after bucket creation, and
   they **override lifecycle rules**, so each lock is set equal to its tier's
   lifecycle rather than longer. Never use the indefinite option — it cannot be
   undone.
4. Create an API token scoped to **this bucket only**, with the narrowest
   permission R2 offers that can upload: *Object Read & Write*. R2 has no
   write-only object permission, so the CI credential can technically download
   ciphertext — which is exactly why confidentiality rests on age rather than on
   token scoping. **The credential cannot decrypt anything, and the bucket lock
   rules are what stop it deleting anything.** Do not use an Admin token; the nightly job
   never needs to manage buckets.

### 3. The database URL

**This is the step that will bite you.** Supabase's *direct* database connection
is IPv6-only and GitHub-hosted runners are IPv4-only, so the obvious connection
string times out.

Use the **session-mode pooler**:

```
postgresql://postgres.<project-ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres
```

Port **5432**, not 6543 — the transaction-mode pooler does not support `pg_dump`.

### 4. Repository secrets

| Secret | Value |
|---|---|
| `PRODUCTION_DB_URL` | Session pooler URI for production |
| `STAGING_DB_URL` | Same for staging (lets you rehearse against a throwaway) |
| `BACKUP_S3_ENDPOINT` | `https://<account-id>.r2.cloudflarestorage.com` |
| `BACKUP_S3_BUCKET` | Bucket name |
| `BACKUP_S3_ACCESS_KEY_ID` | Write-only token |
| `BACKUP_S3_SECRET_ACCESS_KEY` | Write-only token |

---

## Running a backup

Nightly at **08:00 UTC** — after the 22:00 UTC reminder cron, and outside likely
deploy hours. Objects land at `<target>/daily/<timestamp>/`, with copies
promoted to `weekly/` on Sundays and `monthly/` on the 1st.

On demand: **Actions → Backup → Run workflow**, choosing `production` or
`staging`. Do this against staging first — it exercises every step without
touching production.

Locally, against a running local stack:

```sh
DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
PGSSLMODE=disable \
OUT_DIR=/tmp/dr-out \
AGE_RECIPIENT="$(grep -oE 'age1[0-9a-z]+' supabase/dr/backup-recipient.age.pub)" \
./supabase/dr/dump.sh
```

Omitting `AGE_RECIPIENT` leaves the output **unencrypted** and prints a loud
warning. That's fine for a local drill and must never be uploaded.

The script has two safety behaviors worth knowing:

- It **refuses to write into an existing `OUT_DIR`**, so a half-populated
  directory from a failed run is never uploaded as though it were complete.
- If it fails before encryption finishes, it **deletes the whole output
  directory**, so plaintext copies of everyone's data are never left behind. The
  CI action independently re-checks that nothing unencrypted is about to be
  uploaded.

### Verifying a backup by hand

The full procedure — including the tools you need, why it must be run outside the
repository, and cleaning up the decrypted copy afterward — is
**[PROVISIONING.md § 5c](supabase/dr/PROVISIONING.md#5c-prove-you-can-read-it-back)**.
It is kept in one place on purpose: a verification procedure that exists in two
places drifts, and the copy you follow during an incident will be the stale one.

In short: download the prefix, `age -d` each artifact, check every file against
the `sha256` map inside `manifest.json`, and confirm `auth_user_count` equals the
`scholars` row count. Do it at least once per quarter — an untested backup is a
hypothesis.

## Restoring

Every restore follows the same shape. Deviating from it is how a recovery turns
into a second incident.

### The procedure

> **You do not need Postgres installed.** [supabase/dr/psql.sh](supabase/dr/psql.sh)
> runs psql through a container and takes any argument psql does — `-c`, `-f`
> (paths resolve from the repository root), or nothing for an interactive shell.
> `dump.sh` and `drill.sh` already work this way; this exposes it for the manual
> steps, so a recovery never stalls on `psql: command not found`.
>
> ```sh
> DB_URL="postgresql://postgres.<ref>:<pw>@aws-0-<region>.pooler.supabase.com:5432/postgres" \
>   ./supabase/dr/psql.sh -c "select 1"
> ```
>
> The Supabase dashboard's SQL editor is **not** a substitute for the scripts:
> `quarantine.sql` and `rearm.sql` use psql meta-commands (`\echo`,
> `\set ON_ERROR_STOP`) that it cannot run.


**0. Decide the target.** Restoring *over* a live database is almost never right.
Restore into a fresh project, or into a scratch schema, and move the rows you
need. The one exception is a total loss, where there is nothing to protect.

**1. Fetch and verify before touching anything.** Check the artifacts against the
manifest's own SHA-256 map, then read the manifest: `db.migrations` tells you
which schema this data belongs to. Restoring a dump into a tree at a different
migration state is a mismatch worth catching now.

**2. Quarantine — BEFORE you destroy anything.**

```sh
DB_URL=... ./supabase/dr/psql.sh -f supabase/dr/quarantine.sql
```

Order matters more than it looks. `quarantine.sql` records the realtime
publication's membership, and **the dump does not carry it** — publications are
database-level objects, so `pg_dump --schema=public` emits nothing for them. Drop
`public` first and the publication empties, quarantine records zero tables, and
you finish with a restore where every row and every policy is present and
realtime is silently dead on all 14 tables. The app loads and simply stops
updating.

Its record lives in a `dr` schema, not `public`, so it survives the drop. Re-runs
keep the first capture rather than overwriting it, for the same reason.

**3. Apply the schema** — `supabase db push`, or `pg_restore --section=pre-data`.

**4. Quarantine (again, harmless).**

```sh
DB_URL=... ./supabase/dr/psql.sh -f supabase/dr/quarantine.sql
```

Disables the email trigger, unschedules cron, drops the realtime publication, and
records exactly what it changed so step 7 can reverse it.

**5. Load the data.**

```sh
# Portable shape: pg_restore writes SQL to stdout, psql applies it in one session.
{ echo "set session_replication_role = replica;"
  pg_restore --data-only --no-owner --no-privileges -f - public.dump
} | DB_URL=... ./supabase/dr/psql.sh -v ON_ERROR_STOP=1 --single-transaction
```

Load `auth.dump` the same way. A `public`-only restore is not restorable:
`scholars.id` references `auth.users(id) ON DELETE CASCADE`, so without it every
scholar orphans.

Two notes on the `set session_replication_role = replica`:

- It suppresses every user trigger for the session — verified directly against
  this schema. It is cheap insurance rather than a strict requirement here: in a
  full `pg_restore`, triggers live in the post-data section and are created
  *after* the data lands, so they do not fire on restored rows. Tested both with
  and without, restoring into a schema that already had all 16 audit triggers:
  neither produced a single manufactured row.
- Prefer it over `pg_restore --disable-triggers`, which emits
  `ALTER TABLE … DISABLE TRIGGER ALL` and needs more than table ownership — it
  may well fail against hosted Supabase. **Confirm which of the two your role can
  actually do during a drill, not during an incident.**

**6. Replay forward, if you have a tail.**

```sh
TAIL_DIR=/tmp/tail \
FROM_SEQ=<db.watermarks.audit_log from the restored manifest> \
TARGET_DB_URL=... ./supabase/dr/replay.sh
```

This loads the tail's rows and applies every `audit_log` entry past the
watermark, in `seq` order — which respects foreign-key causality for free,
because the original writes did.

> **Replay before anything else writes, including before re-arming.** `seq` is an
> identity column, so after a restore it resumes from the restored maximum and any
> write in between takes the very numbers the tail is carrying. `rearm.sql` stamps
> every scholar's reminder timestamp, which is enough to collide — that is exactly
> what happened the first time this was tested, and the replay reported success
> having quietly applied the wrong rows. `replay.sh` now refuses to run if
> `audit_log` has moved past the watermark, and says so.

**Here the trigger suppression is not optional.** Replay issues ordinary
`INSERT`/`UPDATE` statements against a schema whose triggers are live, so without
`session_replication_role = replica` every replayed row manufactures a fresh
`audit_log` and `token_events` entry dated today — fabricating a history in which
the whole economy moved at the moment of the restore. It is also what stops the
transaction immutability trigger from rejecting perfectly good historical rows.

**7. Verify before re-arming.** Every table count and `auth_user_count` against
the manifest, `npm run test:rls` to prove policies and grants survived, and
`tokens_as_of()` against `tokens` to prove the ledger agrees with state.

**8. Re-arm.**

```sh
DB_URL=... ./supabase/dr/psql.sh -f supabase/dr/rearm.sql
```

Rebuilds the publication from what quarantine recorded, reschedules cron,
re-enables mail last, and stamps the reminder timestamps to suppress one cycle —
see below. It then prints what only a human can do: re-enter the vault secrets,
deploy the edge functions, and repoint the app.

**9. Re-apply erasures.** Any scholar who exercised their right to be forgotten
is alive again in restored data. This is mandatory, not optional. (The `erasures`
ledger arrives with the GDPR work; until then, keep the list by hand.)

### Why reminders get suppressed

Reminder de-duplication is stamped in the data — `scholars.status_reminder_time`
and `venues.transaction_reminder_time`. Restoring to a point before those stamps
re-arms reminders that already went out, so the next cycle mails real people a
second time. `rearm.sql` stamps everything to now, costing at most one skipped
cycle. The asymmetry is the argument: a skipped reminder is a minor annoyance,
duplicate mail to every scholar is not.

### Scenarios

| # | Situation | Approach |
|---|---|---|
| 1 | Total project or account loss | The full procedure into a fresh project. This is the only case where "restore everything" is the right answer. |
| 2 | Bad migration | Restore the pre-migration snapshot, then replay `audit_log` past the watermark the deploy recorded. Revert the migration in the repo before redeploying, or the next deploy repeats it. |
| 3 | Malicious or erroneous privileged actor | The Object-Locked daily copy is the one a stolen credential cannot have deleted. Restore it to a **scratch** project, diff against live, and re-insert only what is missing. |
| 4 | One venue, one submission, one row | `pg_restore --data-only -t <table>` into a `restore` schema, then `insert … select` the specific rows. Never restore over a live table. |
| 5 | Accidental cascade delete of a scholar | Re-create the `auth.users` row with the same uuid; the FKs and `on_auth_user_created` re-link. `token_events` is FK-free by design, so the token history was never lost. |
| 6 | Balances look wrong after a deploy | **No restore.** Diff `tokens` against `tokens_as_of('<before the deploy>')` and repair only the difference. This keeps every legitimate transaction that happened since. |
| 7 | A scholar's data must stay deleted | `public.erasures`, re-applied at step 8 of every restore. |

Scenario 6 is the common one in practice, and the only one that costs nothing:
it is a query and a targeted update, not a recovery.

## Drills

[supabase/dr/drill.sh](supabase/dr/drill.sh) restores a backup into a throwaway
database and **asserts the result against the manifest** — every table's row
count, `auth.users` against `scholars`, the append-only watermarks, the RLS
policy count, and whether `tokens_as_of()` still agrees with `tokens`. "The
restore finished" is a feeling; these are facts.

```sh
BACKUP_DIR=/tmp/backup \
TARGET_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
AGE_IDENTITY=/tmp/backup-identity.txt \
./supabase/dr/drill.sh
```

[.github/workflows/backup-drill.yml](.github/workflows/backup-drill.yml) runs it
monthly at 09:00 UTC on the 1st against the newest real backup in object storage,
into a fresh Supabase stack on the runner, and finishes with `npm run test:rls` —
because row counts prove the data came back, and only the policy tests prove the
*security* came back.

### Measured restore time

| Date | Target | Time | Notes |
|---|---|---|---|
| 2026-08-04 | local stack | 8s | first drill |
| 2026-08-08 | **hosted production** | **33s** | first hosted rehearsal; 1 scholar |

Update after each run.

Read it narrowly. It covers decrypt, checksum verification, quarantine, and the
restore of schema, data, and auth into an already-provisioned stack. It does
**not** include provisioning a Supabase project, applying migrations, re-entering
vault secrets, deploying edge functions, or repointing the app — which is most of
the wall-clock time in scenario 1. It is also measured against a near-empty
database; it will grow with the data.

### What the drills found

Both findings below were invisible to every test in the repository, and each
would have produced a restore that looked completely successful.

**A bare Postgres database is not a valid restore target.** Restoring into one
completed successfully, matched every single row count, and silently produced a
database with **29 of 71 RLS policies missing** — because every policy calls
`auth.uid()` and the `auth` schema did not exist. Row counts alone would have
called that restore a success.

`drill.sh` now refuses such a target up front rather than reporting a puzzling
policy-count mismatch later. The practical consequence: drill into a provisioned
Supabase project or a local `supabase start` stack, never a plain database.

**The realtime publication and the extensions are not in the dump.** Both are
database-level objects, so `pg_dump --schema=public` emits nothing for either. A
restore brings back every row and every policy while leaving realtime dead on all
14 tables and `pg_net` absent — the app loads, stops updating live, and silently
sends no mail. `quarantine.sql` captures the publication (into a `dr` schema, so
it survives `drop schema public cascade`), `dump.sh` captures the extensions, and
`drill.sh` asserts both. **Quarantine must run before anything is dropped**, or it
records an empty publication.

**Grants are not policies, and losing them is invisible.** The dump was taken
with `--no-privileges`, which strips every `GRANT`. A rehearsal restore therefore
produced production with all 71 RLS policies, every row, correct watermarks, an
intact ledger — and **no table privileges for `anon` or `authenticated`**.
PostgREST connects as exactly those roles, so the database was complete and served
nothing; the app rendered "Unable to load" on every page. Every assertion in the
drill passed, because none of them looked at privileges.

`dump.sh` no longer passes `--no-privileges` (nor does the restore), the manifest
records a `grant_fingerprint` covering table *and* column grants — the column ones
carry the INSERT/UPDATE allowlists that `20260802010000` relies on — and
`drill.sh` asserts it, plus a direct `has_table_privilege('anon', …)` check.

### The drill needs a private key — use a second recipient

The automated drill has to decrypt, so CI needs an identity. Giving it the offline
one would be wrong; giving it nothing means the drill never runs.

The answer is a **second recipient on the same artifacts**. `age` encrypts a file
once and wraps the key for each recipient, so adding one costs a few dozen bytes
rather than a second copy, and either key opens the file independently.

- Your **offline** key stays the primary and is never in CI.
- A **drill** key lives in CI as `BACKUP_AGE_IDENTITY`, and can be rotated on its
  own by removing its public key from `backup-recipient.age.pub`. Old backups stay
  readable with the offline key.

Both public keys go in `supabase/dr/backup-recipient.age.pub`, one per line; the
dump action passes every `age1…` it finds.

> **On the "CI can write but not read" property.** Handing CI a decryption key
> does weaken it — but less than it appears, because CI already holds
> `PRODUCTION_DB_URL`. Anyone who compromises Actions can dump the database
> directly, so withholding a key protects little that is not already reachable.
> What the encryption genuinely protects is the artifacts **at rest in R2**,
> against a leaked bucket credential or a storage-provider compromise, and that is
> unaffected by who holds a key. The earlier design here called for a separate
> short-retention `drill/` copy; a second recipient achieves the same isolation
> with none of the machinery.

### Quarterly, by hand

The automated drill cannot exercise everything: `roles.sql` against a real hosted
auth stack, extension availability, the vault, `pg_cron`, `pg_net`, edge function
deploys, or the Vercel repoint. Once a quarter, walk this document by hand into a
throwaway hosted project and record how long it took. Don't automate that one —
the value is a human finding the step that has gone stale.

## Related

- [ARCHITECTURE.md](ARCHITECTURE.md) — deployment pipeline and database management
- [supabase/dr/dump.sh](supabase/dr/dump.sh) — the backup itself, commented at length
- [supabase/dr/manifest.sql](supabase/dr/manifest.sql) — what gets recorded and why
