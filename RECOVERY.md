# Recovery

How Reciprocal Reviews' data is backed up, and how to get it back.

The token economy is not a cache. A scholar's balance is reviewing labor they
actually performed, and there is no upstream system it can be re-derived from —
if it's gone, it's gone. This document is what stands between an incident and
that outcome.

> **Status.** The nightly off-platform backup described here is in place. The
> restore runbook — per-scenario procedures, the quarantine and re-arm scripts,
> and the rehearsal drill — lands with the next phase. Until then, **a restore
> has never been rehearsed**, so treat the recovery time below as an estimate
> rather than a measurement.

---

## What you can currently recover from

| | Covers | Recovery point |
|---|---|---|
| **Nightly encrypted dump** (this repo) | Project loss, account loss, bad migration, logical corruption, malicious deletion | up to **24h** of data loss |
| **Supabase's own backups** | Infrastructure failure | plan-dependent; see below |

**Point-in-time recovery is not enabled.** Supabase offers PITR as a paid add-on
(~$100/mo/project) giving roughly 2-minute granularity; without it, the nightly
dump's 24h window is the real recovery point objective for everything. The
ledger phase narrows this to about an hour for the token economy by exporting
the append-only log more frequently — that is the whole reason the ledger exists.

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
| `cron.json` | The `cron.job` table |
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

The full runbook — total project loss, bad migration, malicious deletion,
single-row surgery, accidental cascade delete, and ledger divergence — arrives
with the next phase, together with the `quarantine.sql` / `rearm.sql` scripts
that make a restore safe to perform at all.

**Do not attempt a restore from these artifacts without those scripts.** Four
hazards fire on a naive restore, and each one reaches real people:

1. **Restoring the `emails` table re-sends every historical email.** The
   `send_on_email_insert` trigger POSTs the `resend` edge function per row.
2. **A restored clone starts mailing scholars**, because `cron.job` comes back
   with the `remind-daily` schedule intact.
3. **Reminder de-duplication is stamped in the data**
   (`scholars.status_reminder_time`, `venues.transaction_reminder_time`), so
   rolling back past those stamps re-arms reminders that already went out.
4. **Realtime fans every restored row at every connected client**, and each one
   triggers `invalidateAll()`.

The short version of the safe procedure: quarantine the target first (disable the
email trigger, blank the vault secrets, unschedule cron, drop the realtime
publication), then load, then re-arm deliberately.

---

## Related

- [ARCHITECTURE.md](ARCHITECTURE.md) — deployment pipeline and database management
- [supabase/dr/dump.sh](supabase/dr/dump.sh) — the backup itself, commented at length
- [supabase/dr/manifest.sql](supabase/dr/manifest.sql) — what gets recorded and why
