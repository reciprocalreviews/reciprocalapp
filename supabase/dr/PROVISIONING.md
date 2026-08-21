# Backup provisioning runbook

One-time setup to make the nightly backup ([.github/workflows/backup.yml](../../.github/workflows/backup.yml))
actually run. Until every step here is done, the workflow fails each night by
design, naming whichever secret is missing.

Keep this document even after setup: if the Cloudflare account is ever lost or
has to be moved, this is the procedure for rebuilding it.

Five parts, in order. **Part 1 first** — it is the only step that cannot be redone
later.

---

## Part 1 — The age keypair

**Do this on your own machine, never in CI.** The private key existing in CI
would defeat the entire design: the point is that the process which writes
backups cannot read them.

```sh
brew install age
cd ~/Desktop            # somewhere temporary
age-keygen -o backup-identity.txt
```

Output looks like:

```
Public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

The file itself contains both halves:

```
# created: 2026-08-03T...
# public key: age1ql3z7...
AGE-SECRET-KEY-1QQPQ...
```

Then, in this order:

1. Copy the **public key** into the repo:

   ```sh
   echo 'age1ql3z7...' > supabase/dr/backup-recipient.age.pub
   ```

   This file is safe to commit — it can only encrypt.

2. Put `backup-identity.txt` in **two** places before continuing:
   - your password manager (as a secure note, full file contents)
   - an offline copy — a printout in a safe, or an encrypted USB drive

3. Delete the working copy:

   ```sh
   shred -u ~/Desktop/backup-identity.txt   # macOS: rm -P
   ```

> ⚠️ **If you lose this key, every backup you hold becomes permanently
> unreadable.** There is no reset and no support path. Confirm you can read it
> back from both locations before moving on.

---

## Part 2 — Cloudflare R2

### 2a. Enable R2

1. Sign in at [dash.cloudflare.com](https://dash.cloudflare.com). Use an account
   **whose recovery you control** — ideally not tied to a single university SSO
   that could be deprovisioned.
2. Sidebar → **R2 Object Storage** → **Enable R2**.
3. A payment method is required even on the free tier. Add one.
4. **Turn on 2FA for this account.** It now holds the only independent copy of
   the database.

Cost in practice: a current dump is ~200 KB. The free tier covers 10 GB storage,
1M writes/month, and **zero egress fees** — which is why R2 rather than S3, since
drills pull whole backups back down.

### 2b. Create the bucket

1. **R2** → **Create bucket**
2. Name: `reciprocal-backups`
3. Location: **Automatic**, or a hint away from your Supabase region so the
   backup sits in a different failure domain

There is nothing to configure at creation time — R2's immutability feature is
added afterward (2d), unlike S3's Object Lock which must be enabled at creation.

4. Note your **Account ID** (bucket page sidebar, or the dashboard URL). The
   endpoint is:

   ```
   https://<ACCOUNT_ID>.r2.cloudflarestorage.com
   ```

   If you chose the EU jurisdiction: `https://<ACCOUNT_ID>.eu.r2.cloudflarestorage.com`

### 2c. Retention lifecycle rules

Bucket → **Settings** → **Object lifecycle rules**. Add three:

| Rule name | Prefix | Action |
|---|---|---|
| `expire-daily` | `production/daily/` | Delete after **14** days |
| `expire-weekly` | `production/weekly/` | Delete after **56** days |
| `expire-monthly` | `production/monthly/` | Delete after **730** days |

Add matching `staging/...` rules with short retention (7 days) so test runs don't
accumulate.

### 2d. Bucket lock rules — immutability

This is what makes backups survive a stolen CI credential: a locked object cannot
be deleted before its retention expires, by anyone, including an attacker holding
the token and including you.

**R2 does not implement S3-style Object Lock.** The equivalent is **bucket
locks**: prefix-scoped rules added *after* creation, with no per-object legal
hold and no governance-vs-compliance toggle. If you need literal S3 Object Lock
API compatibility, R2 will not give you that; if you need WORM retention, it
will.

Bucket → **Settings** tab → **Bucket lock rules** card → add two:

| Rule | Prefix | Retention |
|---|---|---|
| `lock-daily` | `production/daily/` | **14 days** |
| `lock-weekly` | `production/weekly/` | **56 days** |

Equivalently, from the CLI:

```sh
npx wrangler r2 bucket lock add reciprocal-backups
```

Three properties that drive the numbers above:

- **Locks override lifecycle rules.** A lifecycle deletion will not fire while a
  lock still requires retention, so effective retention is `max(lock, lifecycle)`.
  Each lock above is therefore set *equal* to its tier's lifecycle, so the
  retention schedule means what it says. Set a 30-day lock against a 14-day
  lifecycle and you silently get 30-day retention.
- **Rules apply to existing objects too**, not just new ones, and where rules
  overlap the longest retention wins.
- **Scope every rule to a prefix.** A rule covering the whole bucket would also
  lock `staging/`, and **a bucket cannot be emptied while any lock rule exists** —
  which would make routine cleanup of throwaway staging runs impossible.

> **Never choose the indefinite option.** Indefinite locks cannot be removed, and
> deleting a lock *policy* does not release objects already inside their
> retention window — those stay locked until it expires. An indefinite lock on a
> database containing personal data is a commitment you cannot walk back.

**`production/monthly/` is deliberately left unlocked.** The threat this defends
against is a compromised credential deleting your recent recovery points, and 14
days of immutable dailies plus 56 days of immutable weeklies is well past any
realistic detection window. Leaving the two-year tier deletable preserves a path
for correcting mistakes and for honoring an erasure request without a
multi-year wait.

> **On erasure and backups:** a scholar's deletion request cannot reach inside a
> locked backup. That is normal and defensible — backups are retained under a
> documented schedule, and the erasure is re-applied on restore (the `erasures`
> ledger, next phase). It is defensible *because* the retention is bounded and
> written down, which is another reason not to lock anything indefinitely.

### 2e. The API token

Cloudflare has three separate token surfaces, and only one of them works here:

| Surface | Issues | Use for backups? |
|---|---|---|
| My Profile → **User API Tokens** | Cloudflare REST bearer token | **No** |
| Manage Account → **Account API Tokens** | Cloudflare REST bearer token | **No** |
| **R2 → API → Manage API Tokens** | **S3 Access Key ID + Secret Access Key** | **Yes** |

Only R2's own flow issues S3-compatible credentials. The other two produce a
bearer token for Cloudflare's REST API, which `aws s3` cannot use. If what you
are holding is one long opaque string rather than a key/secret *pair*, you are on
the wrong screen.

1. **R2** → **API** → **Manage API Tokens** → **Create API Token**
2. If offered a choice of **Account** vs **User** API token, choose **Account**.
   A user-owned token dies with the personal login it hangs off — if that account
   is removed or rotated, the nightly backup silently starts failing. An
   account-owned token survives personnel changes, which matters for a job whose
   entire purpose is to still work on the worst day.
3. Name: `reciprocal-backup-ci`
4. Permission: **Object Read & Write** — *not* Admin.
5. **Specify bucket** → `reciprocal-backups` only
6. TTL: **Forever**, or set a calendar reminder to rotate
7. Create, then copy these **once** (they are never shown again):
   - **Access Key ID** → `BACKUP_S3_ACCESS_KEY_ID`
   - **Secret Access Key** → `BACKUP_S3_SECRET_ACCESS_KEY`

   Ignore the bearer "Token value" also shown — that is for Cloudflare's REST
   API and is not used here. The endpoint displayed should match the
   `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` from 2b.

> R2 has no write-only object permission, so this credential can technically
> download ciphertext. That is fine and expected: **confidentiality rests on age
> encryption, not on token scoping** — the credential cannot decrypt anything —
> and the bucket lock rules (2d) are what stop it deleting anything.

---

## Part 3 — The Supabase pooler URL

**The step most likely to bite you.** Supabase's direct database connection is
IPv6-only; GitHub-hosted runners are IPv4-only. You need the *session-mode*
pooler.

1. [supabase.com/dashboard](https://supabase.com/dashboard) → your **production**
   project
2. **Connect** (top bar) → **Connection string** → **Session pooler** tab
3. Copy it. It should look like:

   ```
   postgresql://postgres.abcdefghijklm:[YOUR-PASSWORD]@aws-0-us-west-1.pooler.supabase.com:5432/postgres
   ```

4. Replace `[YOUR-PASSWORD]` with the real database password.

Check all three:

- host contains `pooler.supabase.com` (not `db.<ref>.supabase.co`)
- port is **5432**, not 6543 — the transaction pooler cannot do `pg_dump`
- user is `postgres.<project-ref>`, not bare `postgres`

Repeat for the **staging** project.

> If the password contains `@`, `/`, `:`, or `#`, URL-encode it (`@` → `%40`) or
> the URI will not parse.

---

## Part 4 — GitHub secrets

Repo → **Settings** → **Secrets and variables** → **Actions** → **New repository
secret**, six times:

| Secret | Value |
|---|---|
| `PRODUCTION_DB_URL` | Session pooler URI, production |
| `STAGING_DB_URL` | Session pooler URI, staging |
| `BACKUP_S3_ENDPOINT` | `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` |
| `BACKUP_S3_BUCKET` | `reciprocal-backups` |
| `BACKUP_S3_ACCESS_KEY_ID` | From 2e |
| `BACKUP_S3_SECRET_ACCESS_KEY` | From 2e |

Names must match exactly — the workflow checks each one and names any that are
missing.

---

## Part 5 — First run and verification

### 5a. Staging first

**Actions** → **Backup** → **Run workflow** → target `staging` → **Run**.

Expect one to two minutes. The job summary lists the artifacts and their sizes.
On failure, the failing step names the cause — most often the pooler port or a
mistyped secret.

### 5b. Confirm the objects landed

Two tools are needed for 5b and 5c and are not installed by default on macOS:

```sh
brew install age awscli
```

Then set the shared environment for both steps:

```sh
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=auto
export EP=https://<ACCOUNT_ID>.r2.cloudflarestorage.com
export BUCKET=reciprocal-backups
export PREFIX=staging/daily/<timestamp>

aws s3 ls "s3://$BUCKET/staging/daily/" --endpoint-url "$EP"
aws s3 ls "s3://$BUCKET/$PREFIX/" --endpoint-url "$EP"
```

Five objects, every one ending in `.age`.

> **If you see anything not ending in `.age`, stop.** That would mean plaintext
> reached the bucket and both guards failed — `dump.sh` deleting its output on
> failure, and the workflow's pre-upload check.

### 5c. Prove you can read it back

This is the step people skip, and the one that matters. An untested backup is a
hypothesis, not a backup. It is also the only thing that proves the private key
you filed away is the matching half of the public key CI encrypts to — a mismatch
stays silent until the moment you need it.

> **Run this from `/tmp`, never from the repository.** It writes decrypted copies
> of contact emails, ORCID iDs, names, and the full transaction history to disk.
> Inside the working tree that is one stray `git add -A` from being committed.
> Retrieve the private key to a temp path too, and delete it afterward rather
> than leaving it in your home directory.
>
> Pasting the block below into an interactive **zsh** prompt prints
> `command not found: #` for each comment line — zsh only honours `#` as a comment
> when `interactive_comments` is set. It is noise, not a skipped step; `setopt
> interactive_comments` silences it.

```sh
# Save the private key from your password manager to /tmp/backup-identity.txt first.

mkdir -p /tmp/restore-test && cd /tmp/restore-test
aws s3 cp "s3://$BUCKET/$PREFIX/" . --recursive --endpoint-url "$EP"

# Decrypt
for f in *.age; do age -d -i /tmp/backup-identity.txt -o "${f%.age}" "$f"; done

# Checksums must all report OK
jq -r '.sha256 | to_entries[] | select(.key != "manifest.json") | "\(.value)  \(.key)"' \
  manifest.json | shasum -a 256 -c

# Eyeball what it captured
jq '{taken_at, server: .db.server_version, scholars: .db.row_counts.scholars,
     auth_users: .db.auth_user_count, policies: .db.rls_policy_count}' manifest.json

# Clean up both the plaintext and the key
cd / && rm -rf /tmp/restore-test && rm -f /tmp/backup-identity.txt
```

`auth_users` should equal `scholars`. If it does not, the auth dump did not land
and **the backup is not restorable** — `public.scholars.id` references
`auth.users(id) ON DELETE CASCADE`, so without auth every scholar orphans.

### 5d. Then production

Run again with target `production`, repeat 5b–5c, and let the nightly 08:00 UTC
schedule take over.

### 5e. Make failures visible

Scheduled-workflow failures notify only whoever last modified the cron. Confirm
at [github.com/settings/notifications](https://github.com/settings/notifications)
that you will actually receive them. A backup failing silently for three weeks
looks exactly like one that is working.

---

## Checklist

- [ ] age keypair generated; public key committed; private key in password manager **and** offline; working copy shredded
- [ ] Cloudflare account with 2FA; R2 enabled
- [ ] Bucket created
- [ ] Lifecycle rules: 14 / 56 / 730 days, plus short staging rules
- [ ] Bucket lock rules: 14 days on `production/daily/`, 56 days on `production/weekly/` — prefix-scoped, never indefinite
- [ ] API token created from **R2 → API → Manage API Tokens** (not User or Account API Tokens), Account-owned if offered, Object Read & Write, single bucket; key/secret pair saved
- [ ] Both pooler URLs: `pooler.supabase.com`, port **5432**, user `postgres.<ref>`
- [ ] Six GitHub secrets
- [ ] Staging run green; every object ends in `.age`
- [ ] **Decrypted a real backup and verified checksums**
- [ ] Production run green
- [ ] Failure notifications confirmed

---

## What this does and does not buy you

It leaves you at a **24-hour recovery point objective**. Closing that gap is what
the append-only ledger phase is for: restore the nightly dump, then replay the
log forward.

And it makes backups *exist*; it does not yet make restores *safe*. A naive
restore re-sends every historical email and re-arms the reminder cron. The
quarantine and re-arm scripts land in the next phase — see
[RECOVERY.md](../../RECOVERY.md) § Restoring.
