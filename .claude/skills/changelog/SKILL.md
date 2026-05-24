---
name: changelog
description: Analyze uncommitted changes in the working tree and recommend a CHANGELOG.md entry (summary + insertion point) under the most recent version section. Use when the user asks to update the changelog, draft a changelog entry, or summarize pending changes for release notes.
---

# Changelog entry recommender

Analyze the uncommitted changes (staged + unstaged + untracked) in this repo and recommend a one- or two-line entry to add under the **most recent** version section of `CHANGELOG.md`, along with the exact insertion point.

## Steps

1. **Gather the changes.** Run these in parallel:
   - `git status --short` — list all modified/added/deleted/untracked files
   - `git diff HEAD` — full diff of tracked changes (staged + unstaged) vs HEAD
   - For any untracked file relevant to user-facing behavior, read it with the Read tool

2. **Identify the most recent section.** Read the top of `CHANGELOG.md` and locate the first `## <version> - <date>` heading. That is the section to recommend appending to. Do not propose a new version section unless the user asks.

3. **Classify the change.** Decide which subsection it belongs under, using the categories already present in the file:
   - **Added** — new user-facing capability
   - **Changed** — modification to existing behavior, design, or internal tooling that's worth noting
   - **Fixed** — bug fix; reference an issue number (`#NNN`) if mentioned in the diff or recent commits
   - If the change is purely internal (refactor with no behavioral impact, comment-only, formatting), say so and recommend **not** adding an entry.

4. **Draft the entry.** Match the existing prose style of the file:
   - One sentence, past tense or imperative ("Added X.", "Improved Y.", "Fixed Z so that…").
   - User-facing language — describe what a scholar/admin/editor will notice, not the implementation. Internal tooling changes phrase as "Updated internal tooling for stability." or similar.
   - Reference issue numbers as `(#NNN)` at the end if the diff or a recent commit mentions one. Check `git log -5 --oneline` for issue references.
   - Use **bold** for key terms only when the surrounding entries do.
   - If multiple distinct user-facing changes are in the working tree, recommend one bullet per change, each under its appropriate subsection.

5. **Show the insertion point.** Report:
   - The version heading (e.g., `## 0.3.15 - 2026-05-17`)
   - The subsection (`### Added` / `### Changed` / `### Fixed`)
   - The exact line number where the new bullet should be inserted (end of that subsection's bullet list, before the next `###` or `##` heading)
   - If the target subsection doesn't yet exist in the current version, recommend creating it in the canonical order: Added → Changed → Fixed.

6. **Do not write to CHANGELOG.md.** Present the recommendation as a proposal. Only edit the file if the user confirms.

## Output format

Respond with:

```
**Summary of pending changes:** <one-sentence overview of what's in the working tree>

**Recommended entry:**
- <draft bullet> [under ### <subsection>]

**Insertion point:** CHANGELOG.md:<line> — end of `### <subsection>` under `## <version> - <date>`

**Apply this?** (yes / edit / skip)
```

If multiple bullets are warranted, list each with its own subsection and insertion line.

## Notes

- The "most recent" section is the first `## ` heading in the file, not necessarily the highest version number. Trust file order.
- If the working tree is clean (`git diff HEAD` empty and no untracked files of consequence), say so and stop — there's nothing to add.
- Entries already present in the section should not be duplicated. Skim existing bullets before drafting.
- Date format in headings is `YYYY-MM-DD`. The version section's date is when that release was cut, not today — don't modify it when appending entries.
