---
name: update-deps
description: Update out-of-date npm dependencies. Semver-compatible bumps (patch + minor) are applied unconditionally; major bumps trigger codebase impact analysis and a per-package decision request, with a migration plan drafted for each one the user approves. Use when the user asks to update dependencies, check for outdated packages, or upgrade a specific dependency.
---

# Dependency updater

Update outdated npm dependencies in this repo. Apply semver-compatible bumps (patch + minor) without asking. For major bumps, analyze impact on the codebase, surface a decision for each one, and — if approved — draft a migration plan before changing anything.

## Steps

### 1. Detect outdated dependencies

Run in parallel:

- `npm outdated --json` — machine-readable list of outdated packages with `current`, `wanted`, `latest`
- `npm ls --depth=0 --json` — confirm which are top-level (only top-level should be bumped here)

Parse the output and split each package into one of:

- **Safe** — `wanted` differs from `current` (patch or minor under the existing semver range), OR `latest` is the same major as `current`. Apply unconditionally.
- **Major** — `latest` is a higher major than `current` (e.g., `2.x → 3.x`, or `0.5 → 0.6` since `0.x` versions treat each minor as breaking per semver §4). Analyze before touching.

Show the user the two lists before proceeding.

### 2. Apply safe updates

For the safe list:

1. Run `npm update` — this bumps within existing semver ranges and updates `package-lock.json`.
2. For any safe package where `latest` is the same major but outside the current range (e.g., range `^1.2.0`, current `1.2.5`, latest `1.9.0` and want to widen), update the range in `package.json` directly, then `npm install`.
3. Verify nothing broke:
   - `npm run check:now` (svelte-check / TypeScript)
   - `npm run test:unit`
4. If either fails, stop and report — do NOT proceed to major updates with a broken tree.

Report what was bumped (`pkg: a.b.c → x.y.z`) and the verification result.

### 3. Analyze each major bump

For each package in the major list, in parallel where possible:

1. **Fetch release notes.** Use WebFetch on the package's changelog/releases page. Try in order:
   - `https://github.com/<owner>/<repo>/releases` (look up the repo from `npm view <pkg> repository.url`)
   - The package's `CHANGELOG.md` on GitHub
   - `https://www.npmjs.com/package/<pkg>` if the above are unavailable
   Focus on entries between `current` and `latest`. Summarize breaking changes only — skip features/fixes.

2. **Find usage in the codebase.** Grep for the import:
   - `import .* from ['"]<pkg>['"]` and `require\(['"]<pkg>['"]\)`
   - For scoped packages and sub-paths, also grep the bare name.
   Read enough of each call site to understand what API surface this repo actually uses.

3. **Assess impact.** Cross-reference (1) and (2):
   - Which breaking changes touch APIs this repo uses?
   - Which don't apply (we don't use that feature)?
   - Are there transitive concerns (e.g., peer-dep mismatches, type changes)?

### 4. Present a decision per major bump

For each major bump, output:

```
### <pkg>: <current> → <latest>

**Breaking changes in this range:**
- <one-line summary> [<link to release/changelog>]
- …

**Impact on this repo:**
- <file:line> — <how this code is affected, or "not affected because…">
- …

**Recommendation:** <update / hold / skip> — <one-sentence reason>

**Decision?** (update / hold / skip)
```

If a major bump has no real impact (we don't use the affected APIs), say so explicitly and recommend `update`. If impact is significant, recommend `hold` and explain what would need to change.

Wait for the user's decision per package before doing anything.

### 5. Draft a migration plan for each approved major bump

For every major bump the user says `update` to, produce a plan **before** editing:

```
### Migration plan: <pkg> <current> → <latest>

1. <step> — <file:line if applicable>
2. <step>
3. …

**Verification after migration:**
- npm run check:now
- npm run test:unit
- npm run test:end (if the change touches UI/routing/auth)
- Manual smoke (if applicable): <what to click / verify>
```

Present the plan and wait for confirmation before running `npm install <pkg>@<latest>` and applying code changes. Apply one major bump at a time so verification is unambiguous.

### 6. Final report

After all approved updates are applied and verified, summarize:

- Safe bumps applied (compact list)
- Major bumps applied (with version transitions)
- Major bumps held/skipped (with reason)
- Verification status (check / unit / end / manual)
- Anything the user should follow up on (e.g., deprecation warnings introduced, peer-dep nags)

Remind the user that this changed `package.json` + `package-lock.json` and may warrant a `CHANGELOG.md` entry under **Changed** (the `/changelog` command can draft one).

## Notes

- **Do not bypass `npm audit` findings silently.** If `npm install` surfaces vulnerabilities, mention them in the final report — but don't auto-run `npm audit fix --force`, which can introduce its own breakage.
- **Lockfile hygiene:** always commit `package-lock.json` alongside `package.json` changes. Never delete the lockfile to "force" resolution.
- **0.x packages:** per semver §4, every minor bump in `0.x` is allowed to be breaking. Treat `0.x → 0.(x+1)` as a major bump for analysis purposes, even though npm's semver range satisfaction would treat it differently.
- **Pinned versions:** if `package.json` pins exact versions (no `^` or `~`), respect that pin and ask before widening it.
- **Peer dependencies:** if a major bump's peer-dep requirements conflict with another installed package, surface the conflict in step 3 rather than letting npm error out at install time.
- **Don't refactor opportunistically.** Migration plans should change only what the breaking change requires. Anything else is out of scope for this skill.
