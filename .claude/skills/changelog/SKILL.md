---
name: changelog
description: Write the CHANGELOG.md entry for the uncommitted changes in the working tree, under the most recent version section. Use when the user asks to update the changelog, draft a changelog entry, or summarize pending changes for release notes — and ALSO whenever you are about to add or edit an entry in CHANGELOG.md as a step in some larger task, which is the common case and the one that used to slip through.
---

# Changelog entry writer

Work out what the uncommitted changes (staged + unstaged + untracked) mean for a reader, then **write** the entry into the **most recent** version section of `CHANGELOG.md`. Writing it is the point of this skill — do not stop at a proposal and ask whether to apply it.

## Steps

1. **Gather the changes.** Run these in parallel:
   - `git status --short` — list all modified/added/deleted/untracked files
   - `git diff HEAD` — full diff of tracked changes (staged + unstaged) vs HEAD
   - For any untracked file relevant to user-facing behavior, read it with the Read tool

2. **Identify the most recent section.** Read the top of `CHANGELOG.md` and locate the first `## <version> - <date>` heading. That is the section to append to. Do not create a new version section unless the user asks.

3. **Classify the change.** Decide which subsection it belongs under, using the categories already present in the file:
   - **Added** — new user-facing capability
   - **Changed** — modification to existing behavior, design, or internal tooling that's worth noting
   - **Fixed** — bug fix; reference an issue number (`#NNN`) if mentioned in the diff or recent commits
   - If the change is purely internal (refactor with no behavioral impact, comment-only, formatting), add **nothing** and say why.

4. **Draft the entry. Two sentences maximum — a hard cap, not a preference.** The optional **bold headline** does not count against the two; everything after it does. Count them before writing the bullet; one is better. If a third sentence feels necessary it belongs in the commit message, DESIGN.md, or ARCHITECTURE.md — the changelog says what changed for the reader, not why or how it was built.

   The cap **overrides style-matching.** Match the file's _voice_ — user-facing, bold lead-in where the neighbours use one — but never its length.
   - Sentence one: what is different now. Sentence two, if needed: what it was before, or the one consequence the reader has to know.
   - Past tense or imperative ("Added X.", "Improved Y.", "Fixed Z so that…").
   - User-facing language — describe what a scholar/admin/editor will notice, not the implementation. Internal tooling changes phrase as "Updated internal tooling for stability." or similar.
   - Reference issue numbers as `(#NNN)` at the end if the diff or a recent commit mentions one. Check `git log -5 --oneline` for issue references.
   - Use **bold** for key terms only when the surrounding entries do.
   - One bullet per distinct user-facing change, each under its own subsection.

5. **Find the insertion point.** The end of the target subsection's bullet list, before the next `###` or `##` heading. If the subsection doesn't exist yet in the current version, create it in the canonical order: Added → Changed → Fixed.

6. **Write it.** Edit `CHANGELOG.md` directly — no confirmation step. Then:
   - Run `npx prettier --write CHANGELOG.md` if the repo formats markdown (this one does), so the entry doesn't fail `format:check`.
   - Re-read the bullet you wrote and count its sentences one more time. Over the cap is the failure this skill exists to prevent, and it is easiest to catch here.

## Output format

Report what you wrote, briefly — the bullet and where it landed:

```
Added to `### <subsection>` under `## <version> - <date>`:
- <the bullet as written>
```

Nothing else. The user can read the diff; do not restate the change, explain the reasoning, or list what you considered and rejected. If you added no entry, say that in one line and why.

## Notes

- The "most recent" section is the first `## ` heading in the file, not necessarily the highest version number. Trust file order.
- If the working tree is clean (`git diff HEAD` empty and no untracked files of consequence), say so and stop — there's nothing to add.
- Entries already present in the section should not be duplicated. Skim existing bullets before drafting.
- Date format in headings is `YYYY-MM-DD`. The version section's date is when that release was cut, not today — don't modify it when appending entries.
- Editing a **released** section (anything below the top one) is a different job: only do it when the user asks, and preserve each entry's meaning while trimming.
