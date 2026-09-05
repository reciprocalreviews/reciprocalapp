# Changes

Hi! This is where we document all notable changes, including bug fixes, enhancements, and dependency updates. Dates should be in`YYYY-MM-DD` format.

## 0.5.4 - 2026-09-05

### Added

- **The submission importer now reads exports from any reviewing system.** Upload a CSV with whatever column names it arrived with and match them to fields on screen, rather than renaming columns by hand first.
- **A bulk import can now name each submission's editors.** Your file's editor columns are matched to the venue's roles, so an export naming an editor in chief and a handling editor separately seats both. A name matching nobody leaves that submission unseated rather than stopping the import; one matching several people waits for you to choose.
- **The file's own submission-type names are matched too**, each listed with how many rows carry it, so the type an import gives its submissions is chosen rather than silently defaulted.
- **Invite people to a role from the venue page**, not only from the roles step of venue settings. The form sits on the role's own card in both places.
- **The invite field now finds people by name, and several at once.** Type or paste any mix of email addresses, ORCID iDs, and names, separated by commas; everyone each entry matches is offered below the field, and clicking one moves them to the list to be invited and clears the entry that found them. Nothing goes out until you press **Invite**, and only the people on that list are sent to. Someone who already has a record for the role isn't offered, and an entry matching nobody is named without holding up the rest — previously one mistyped address refused the whole batch.

### Fixed

- **A line break inside a title or status column no longer breaks an import.** Every row after it shifted into the wrong columns, which made a file exported straight from a reviewing platform unusable.
- **Reading a CSV now says what it read** and scrolls to it. Nothing acknowledged the file at all, and the rows appeared below the fold behind a control that had gone back to reading "no file chosen".
- **A CSV can now actually be pasted.** The paste box was a single-line field, so a multi-line CSV collapsed onto one line and arrived as a header with no rows.
- **The submissions list no longer says imported submissions were paid for.** Nothing was ever charged for them, and the tokens meant to fund their reviewing are still an unapproved mint, so they now read **free**. The same wrong badge appeared on every submission at a payment-free venue, which no longer shows a payment column at all.
- **An imported submission's expertise can now be edited by its editor.** Imported submissions have no authors and only an author could edit it, so the field reviewers read when deciding what to bid on could be filled in by nobody.
- **Inviting someone to a role no longer reports it twice.** "Invitations sent!" appeared alongside "… was emailed …" for each person; the second says the same thing and names who was told, so the generic one now only appears when nobody could be emailed.
- **Typing a complete email address into a scholar field no longer reports "No matches."** The address was searched for as though it were a name, so a person the field could resolve perfectly well was announced as unfindable.
- **A submission nobody has said what expertise it needs now says so.** The column was simply blank, which read as a page that had failed to load rather than a question the submission had left unanswered.
- **A withheld author list now carries a lock** instead of an anonymous "•••", which the same list also used for "couldn't load" and "sign in to see". The submission page marks a withheld author the same way.
- **The manuscript ID is now withheld from anyone who cannot see the authors.** It is the key the paper is filed under in the venue's own reviewing system, so a bidder could look it up there and read off the author list the venue was hiding — including by typing a guess into the search box and watching whether the row survived.
- **Venue settings no longer promises bidders a "yes/no" bid** when no preference levels are defined. They get a single **Bid** button, with **Unbid** to take it back, which is what the copy now says.
- **The anonymity and assignment guidance now names the setup steps it points at** rather than numbering them. Two of the three numbers were wrong, and the preference-levels step's number changes depending on whether any role takes bids.

## 0.5.3 - 2026-08-31

### Fixed

- **Pages now load faster**, the home page most of all. Arriving at the home page while already signed in briefly shows **Log in** in the header before your profile and token balance appear.

## 0.5.2 - 2026-08-30

### Fixed

- **A venue's ledger now accounts for the tokens its welcome grants create.** When a newcomer's welcome grant was larger than the venue's reserve, the platform minted the difference and passed it straight on without recording where it came from, so the venue's transaction history quietly stopped adding up to its balance. Minting is now recorded as its own entry crediting the reserve, and the venues already affected have had the missing entries added.

## 0.5.1 - 2026-08-28

### Added

- **Volunteering now reaches somebody.** When a scholar volunteers for one of a venue's open roles, everyone in the venue's top role is emailed on one shared thread, with **Reply going to the new volunteer** so answering it is the welcome. Previously nothing happened at all: the venue found out when someone opened its volunteers list, and the newcomer heard nothing back.
- **A setting for notices you'd rather not get.** A scholar's profile now lists the emails that are courtesies rather than consequences, each with a switch. Anything consequential — a charge awaiting approval, a declined transaction, an assignment — is always sent.
- Scholar profiles now show the scholar's **ORCID iD**, linked to their ORCID record, so a visitor can confirm who they're looking at and follow through to the publications and affiliations Reciprocal Reviews doesn't reproduce itself.
- **A new submission now reaches an editor.** A venue with one editor has them assigned on arrival; a venue with several tells all of them a submission is waiting, and the ones nobody is editing are flagged on the submissions list with a filter, a one-click claim button, and a reminder that chases them. Previously nothing was assigned and nobody was told, so a submission could sit unnoticed indefinitely.
- **Venues now have a readable web address.** A venue picks one during setup — `reciprocal.reviews/venue/acm-chi` — and every link to it, in the app and in email, uses that instead of a 36-character identifier. Changing an address releases the old one immediately, so links that used it stop working, and the button says so before you commit.

### Changed

- A venue can now be **approved before its community has found a minter**: approval takes whichever listed editors and minters already have accounts, and if no proposed minter has one, the approving steward holds the currency until the venue names someone. Previously a single unrecognized email address meant the venue couldn't be created at all.
- **A venue's admin can now also mint its currency**, and a venue whose admin does says so on its page to every visitor who is neither, inviting them to take the minting role over. Forbidding the arrangement blocked venues from going live, asked more of a small community than it could staff, and treated the people running a venue as suspects; approving a payment into a venue you run is still refused, since that moves tokens somebody else already holds.
- The venue proposal form now says which listed email addresses don't yet belong to a Reciprocal Reviews account, and a steward sees the same before approving. Neither blocks anything: listed editors are emailed an invitation when the proposal is filed, and are added to the venue when they sign up.
- The button for deleting a proposal now says **Delete** instead of showing only an ✖, and **Approve** carries a matching checkmark.
- **Token balances are now private.** A scholar sees their own; a venue's editors and its currency's minters see the balances of scholars reviewing there, so paid work can go to whoever is most undercompensated; nobody else — including a submission's authors and the reviewers bidding alongside you — sees them at all. Previously any signed-in scholar could read who held how much of what, across every venue on the platform. (#109)
- The new submission form now says which co-authors cannot cover their share of the charge, rather than how many tokens short they are.

### Fixed

- **Erasing an account now removes the address from mail about other people.** Erasure only looked at who a message was addressed to or sent by, so an erased scholar's address could survive as a copied recipient or reply address on a notice about someone else. Your data download likewise now includes mail you were copied on.
- **A volunteer record can no longer be deleted or moved to another venue.** Both were ways to be welcomed by the same venue twice, since the one-time welcome grant is decided by whether you have volunteered there before. Nothing in Reciprocal Reviews offered either action, but the database allowed them to anyone calling the API directly.
- **Joining a second venue now grants that venue's welcome tokens.** A venue's welcome amount is its own standing policy, in its own currency, but the grant was only ever made on the very first role a scholar took anywhere on the platform — so anyone who had already volunteered somewhere received nothing everywhere they went afterward, with nothing on screen to say a welcome had been skipped. Each venue now welcomes a newcomer once, on their first role there.
- Proposing a venue now reliably takes you to the new proposal. The proposal was being created, but the page could silently fail to move you to it and leave the Propose button stuck, with nothing on screen or in the console to say why — a refresh was the only way out.
- An email address listed twice on a proposal is now recorded once, so someone named twice is no longer emailed the same invitation twice.
- **Every role a venue created was silently a top-priority role.** The top role's holders act as the venue's editors — able to approve any assignment, edit a submission's author list, and mark it done — and new roles landed there by default, handing out that authority until an admin used the reorder arrows. New roles are now added at the bottom, venues with tied roles have been renumbered, and the note explaining the top role no longer appears on several roles at once.
- Saving an editable field no longer flashes the old value: the field shows what you typed the moment you save, the button shows that a save is in flight, and it reopens with your text intact if the save fails. Previously it reverted while the save was in progress and switched back a second later, which on a slow connection read as the edit having been lost.
- Validation warnings no longer linger on a field that has been cleared. Fields now stay quiet until you type in them and go quiet again when something clears them — previously a field that emptied after you submitted kept the "must not be empty" warning it earned while you were filling it in.
- **Closed a hole that let anyone mint or move tokens without signing in.** Several database routines that rely on their callers to have already checked permissions were reachable directly through the public API, so a venue's reserve could be emptied and new tokens created from nothing.
- A venue's transactions page no longer shows a loading error when the venue's reserve is empty.
- **An account whose profile was never created now repairs itself.** Signing in for the first time could leave you with an account but no profile, which every page read as not being signed in at all — your own profile reported that it couldn't load, and nothing you could do fixed it — so the missing profile is now created on your next visit.
- **A link to a scholar who doesn't exist now says so.** A mistyped or outdated profile address previously reported that the profile couldn't be loaded, which was indistinguishable from the site being broken.
- **An editor can now add a submission on behalf of scholars.** Filling the new submission form in with someone else's ORCID used to replace the whole submit path with "Only authors of a submission can create a submission," so the only way to record someone else's paper was to list yourself as one of its authors; an editor now starts with an empty author row instead of their own name ([#153](https://github.com/reciprocalreviews/reciprocalapp/issues/153)).

## 0.5.0 - 2026-08-28

### Added

- **Reciprocal Reviews is in public beta.** Every part of the platform is now reachable: you can browse venues, sign in, propose a journal or conference, volunteer to review, and manage a venue. Until now production redirected everything except the landing, about, and updates pages back to the home page.
- Reciprocal Reviews has a **logo** — two arrows chasing each other around a circle — and a [brand page](/brand) listing the mark, the colors, and the typefaces, with the files available to download. It's linked from the footer.
- Link previews now show a proper card with the logo and tagline when a Reciprocal Reviews page is shared, and the browser tab shows the logo rather than a generic icon. Search engines get a `robots.txt` and a sitemap that lists the public pages, the help articles, and every active venue.
- Reciprocal Reviews now has a **help section** and a **contact page**, both linked from the footer. Help answers the questions we're asked most often; contact names the stewards who read your message and gives you one address that reaches all of them.
- Editors can now assign one scholar across several submissions from the submissions list — pick the role and person once, then assign per submission — instead of opening each submission in turn.
- Reciprocal Reviews now follows up on work that stalls: co-authors are emailed when a submission charge awaits their payment, approvers are reminded when a reviewer has requested compensation, and editors are reminded when a submission has all its reviewing paid and is ready to be marked done. Each follows the venue's existing reminder frequency, and pending compensation now also appears in your task list.
- Your **token balance** now appears in the header while you're signed in, counting up or down when it changes, so earning or spending tokens is visible where it happens rather than only on your profile.
- You can now find a co-author by **name** on the new submission form, instead of needing their ORCID to hand. The top three matches appear beside the field; picking one fills in their ORCID.
- Stewards can now **appoint and remove other stewards** from the About page, where the steward list already lived; previously stewardship could only be granted by editing the database directly. A steward can't remove themselves — stepping down is something another steward does for you — and the last steward can't be removed at all.

### Changed

- The landing page leads with **"Make peer review count."** in the flow of the page rather than pinned to the header, and shows what a submission cost looks like — a token chip right in the sentence — instead of only describing one. The newsletter is now linked from the volunteer community note.
- Updated internal tooling for stability.
- You can now **reply to any email** Reciprocal Reviews sends you and reach a person. Replies previously went to an unmonitored address and were lost.
- Notifications to the stewards, such as new venue proposals and alerts about the platform's own health, now arrive in a shared inbox they can work through together. They previously went out as separate copies to each steward, with no way to see whether anyone had picked a request up.
- The new submission form now lists you as the first author, so it's clear you're included and where to set your own payment.
- Email links now lead back to the site that sent them, so test and staging deployments no longer send people to the live site.
- The volunteer confirmation now says how many welcome tokens you actually received, and says nothing about tokens when none were granted. It previously promised tokens "once the minter approves them", which stopped being true when welcome tokens started arriving immediately; accepting a role invitation now confirms as well.
- Welcome tokens now arrive the moment you volunteer, instead of waiting for a currency minter to approve them — the wait previously fell on newcomers volunteering in order to afford their own submission.
- Reviewer bids and candidate assignees are now listed with the **lowest token balance first**, surfacing the scholars most in need of paid reviewing work.
- Approving a transaction now asks for confirmation, since it moves tokens permanently and cannot be undone. Removing a minter, a compensation rate, a preference level, or an assignment now confirm too, and the warnings for deleting a role or submission type now say what else will be deleted.
- Paying for a submission now explains that every author listed must have a Reciprocal Reviews account, and links to volunteering when an author is short of tokens.
- Finding a scholar by **name** now works everywhere you name one, not just on the new submission form: adding a venue admin, adding a currency minter, and inviting someone to a role all offer matches as you type, instead of requiring an exact ORCID iD or email address.

### Fixed

- Text that a venue or a proposal supplies — a venue description, a proposal title — can no longer inject markup into the page it appears on. Values substituted into a sentence are now escaped by default, and only markup the platform generated itself is exempt.
- Token amounts no longer break across lines between the number and the word "tokens". A chip like ★ 10 tokens now stays whole wherever it appears, including in transaction tables and on scholar pages.
- The alert that warns stewards the token ledger may be corrupt is now always delivered. It previously went only to stewards who had verified a contact email address, so the warning that something had gone seriously wrong could reach nobody at all.
- Only a listed author, or an admin of the venue, can create a submission. Any signed-in scholar could previously create one at any venue and leave payment demands against people who had never heard of it.
- Gifting tokens to a venue now requires the same acknowledgement as gifting to a scholar; that confirmation was skipped for venues.
- Venues, currencies, and submissions can no longer be deleted through the API. Nothing in the app offered this, but the permission existed — and deleting a venue would have taken its roles, volunteers, assignments, and compensation rates with it.
- Emails telling you a transaction was declined now carry a working link. The link was arriving mangled and unclickable.
- Listing the same author twice on a submission is now flagged on that author's own row, rather than only in a message at the bottom of the form. Two spellings of the same ORCID that differ only in capitalization are also caught, as the database always did.
- The About page now says so when there are no stewards, instead of showing an empty space between "Current stewards are:" and the invitation to become one. The message when the list fails to load is now marked as an error.
- Erasing an account now also removes any stewardship it held. An erased steward previously stayed on the public steward list as "anonymous" and kept the permissions that go with it.
- Scholar name searches now return the same people in the same order each time, and the steward list is ordered by name too. Results were previously in whatever order the database happened to return, which shifted whenever anyone's profile was edited — so searching the same name twice could offer different scholars.
- Each name-search result now identifies the scholar to screen readers. Every match previously announced the same generic label, making a column of them impossible to tell apart.
- Adding a venue admin now reports validation problems in the page's language, rather than in hardcoded English.

## 0.4.7 - 2026-08-16

### Changed

- Updated internal tooling for stability.
- Submission charges are now checked by the database as well as the form: the amounts must add up to the submission type's cost, and the same author can't be listed twice. Previously these rules held only for people submitting through the form.

### Fixed

- Bulk CSV imports now warn when a row's columns don't line up with the header. An unquoted comma in a title used to shift every column and silently drop the last field, so an import could land with the wrong manuscript IDs and still look successful.
- The balance check when paying for a submission now counts only the venue's own currency. It previously counted tokens from every venue, so the check could pass and the payment then be refused.
- Reviewer bids now sort predictably in venues that haven't set up preference levels; their order was previously arbitrary.
- The submissions list now breaks ties correctly when several submissions share a date.
- Exporting volunteers as CSV no longer truncates the file at the first #, so an expertise like "C#" no longer cuts the download short.
- Number, web address, and email fields now reject malformed input instead of accepting text that merely contains a number or a link. A venue's welcome amount could previously be set to a value that failed to save.
- Links in emails that end a sentence no longer include the trailing punctuation in the link, and escaped text no longer reappears as markup in the plain-text version.

## 0.4.6 - 2026-08-08

### Changed

- Updated internal tooling for stability.

### Added

- Scholars can now **download everything** Reciprocal Reviews holds about them, and **erase their account**. Erasing permanently removes your name, email address, and ORCID iD; your reviewing and payment records remain without your name attached, because they are part of other scholars' histories too, and the tokens you earned stay valid currency for the venues that issued them. (#13)

### Fixed

- Token ownership can now only change through a **recorded transaction**. Previously a scholar could transfer their own tokens directly with no record of the transfer, or relabel a token into a currency no one had granted them.
- Transactions are now permanent for everyone: they can no longer be deleted by currency minters, and a transaction's identity and timestamp are set by the platform rather than by whoever proposed it.
- If the platform ever suffers a serious failure, it can now recover to within about an hour of it rather than losing up to a day of work.
- The internal record of who changed what is now genuinely permanent: the audit tables could previously be modified by the platform's own service credentials, and can no longer be. Automated checks now verify that the platform's description of its own database matches the real thing, so a stale description can't quietly mislead a recovery.

## 0.4.5 - 2026-07-19

### Added

- ORCID authentication as the sole means of login (#19, #27).

### Changed

- Updated internal tooling for stability.

## 0.4.4 - 2026-06-28

### Added

- Authors can now send a short note of **thanks** to the reviewers of a completed submission; by default an editor reviews the note before it's shared, and reviewers stay anonymous to the author. (#22)

### Changed

- Gave all platform emails a consistent branded look — both sign-in/authentication emails and notification emails — and routed authentication email through the same provider (#56).
- Improved onboarding guidance (#65).
- Updated internal tooling for stability.

## 0.4.3 - 2026-06-14

### Changed

- Updated internal tooling for stability.
- Made the pay prompt on the venue page much more prominent, since it is the central functionality of the platform.
- Clarified on venue proposal that editors will be emailed (#138).
- Extracted all Supabase reads from page load functions to CRUD interface for better encapsulation (#137).

## 0.4.2 - 2026-06-07

### Added

- Beta mode (#135).
- Payment-free mode, to support volunteer tracking value proposition (#123).
- Migrated non-atomic CRUD operations to RPCs for data integrity guarantees (#136).

### Changed

- Updated internal tooling for stability.
- Reduced end-to-end test and deploy time to ~5 minutes, while also increasing reliability.
- Added end-to-end tests for scholar profile updates and gifting (#116).

## 0.4.1 - 2026-05-31

### Added

- Submissions can now be **explicitly linked to a prior submission** to represent revise-and-resubmit chains: authors pick one of their earlier submissions to the same venue from a dropdown, which fills and locks the external manuscript ID field and **auto-selects the matching revision submission type**. The free-text ID stays available for predecessors that aren't on the platform, and bulk imports best-effort resolve their external `previousid` to an on-platform link. (#124)

### Changed

- **Submission cost is now set per submission type** instead of venue-wide, since each type is a different amount of work; admins edit each type's cost in the submission types table on the venue dashboard, and the venue-wide setting is gone. Because a resubmission is its own revision type, it simply carries its own cost. (#124)

- Tightened access control across the database: a submission's assigned reviewers are now visible only to the assignee, the role's approver chain, and venue admins — plus the submission's authors when a venue runs **open (non-anonymous) review** — and a declared conflict always hides that submission's assignments. Currency **minters can now only mint tokens, not move existing ones** (reserve payouts are made by editors), and token balances, compensation amounts, and bid-preference levels are no longer visible to signed-out visitors.

- Added a full-coverage test suite of all table's RLS rules (#79).

- Updated internal tooling for stability.

### Fixed

- Completed submissions and recorded transactions are now genuinely immutable: a submission's `status`/`completed_at` and a transaction's identity fields can no longer be edited directly through the API (a previous column-permission lock was silently ineffective). (#79)

## 0.4.0 - 2026-05-24

### Added

- Invited scholars can now **accept** or **decline** an invitation directly from the role card or their task list, with both actions requiring a confirm. Pending invitations also surface in the scholar's task list and the relevant role card auto-expands on the venue page. (#128)
- The submissions filter on a venue's submissions page now matches **author** and **assigned reviewer** names in addition to title and external ID, respecting reviewer- and author-anonymity flags. The list also shows authors in a new column (where visible to the viewer) and highlights cells whose content matches the filter. (#125)
- The proposer of a transaction is now emailed when a minter or editor **declines** it, with the decliner's name (and contact link), the reason, and a link back to follow up. The transactions page also shows the decliner and reason inline on declined rows, and the original purpose is preserved alongside the new audit columns. (#114)
- The submission detail page now shows each candidate scholar's **active assignment count against their stated paper-count cap** in a new "Assignments / Limit" column (with cross-venue load shown as a secondary indicator), and approving an assignment that would push the scholar over their cap now requires a second click to confirm. (#126)
- Venue editors can now copy ready-to-paste **email-template snippets** for author submission payment, assignment acknowledgement, and compensation requests from the venue's settings page, with the manuscript-ID variable rendered in the syntax of the chosen reviewing platform (HotCRP, EasyChair, ScholarOne, Editorial Manager, OJS, OpenReview, PCS, or plain text). The deep-link URLs in those snippets pre-fill the manuscript ID on the destination page so recipients land in the right form, ready to submit. (#113)

### Changed

- Renamed the "Cancel" action on proposed transactions to **Decline** throughout the UI (button labels, status badge, error messages), to better match its meaning as an active, accountable decision. (#114)
- Reworked the venue settings page as a **numbered setup workflow**: a "Decide policies" primer at the top lists the community decisions to make first, then each section is a numbered step, with Activate always last. Sections renumber automatically when one is hidden (Bid preference levels disappears if no role allows bidding), and per-role cards start collapsed so the page stays scannable.
- Updated internal tooling for stability.

### Fixed

- Fixed an issue where scholars who accepted an invitation to a role kept their volunteer status as "invited" instead of advancing to "accepted," so editors filtering for confirmed volunteers wouldn't see them. (#127)

## 0.3.15 - 2026-05-17

### Added

- A submission can now be marked **done**, finalizing review and compensating its editor(s) in one action.
- Submissions list now shows a per-submission **Progress** column (in review / done). Done submissions sort to the bottom of the list regardless of other sort order, and are hidden from the list after a venue-configurable window.
- New venue setting: how long do fininshed submissions remain visible? They remain accessible by direct link.
- Made subheaders linkable.
- Wrote and wired up terms of service and privacy. Thanks to Andrew Petersen for the writing and research! (#13)
- Added customizable reminder frequency for minting and transaction reminders.
- Added preference levels to bidding (#122).
- Added paper count limits to assignments (#129).

### Changed

- Improved form design.
- Updated RLS policies and front end to prevent "self-dealing": scholars who enrich themselves with tokens, without oversight.
- Updated internal tooling for stability.

## 0.3.14 - 2026-05-10

### Added

- End-to-end tests for venue administration (#121), currency minting and transaction approval (#120), role configuration and volunteering (#118), submission and assignments (#119), and venue proposal (#117).

### Changed

- Volunteers in an approving role can now approve and compensate other volunteers' work directly. Rather than an Associate Editor marking a review approved and then a minter approving the resulting transaction, the Associate Editor approves the transfer from the venue themselves — a transaction is still generated for transparency and auditing.
- Updated DESIGN.md to be alignment with the current design and technical debt. Also updated CLAUDE.md to maintain DEISGN.md and ARCHITECTURE.md in response to changes in implementation.
- Updated ARCHITECTURE.md to be a more complete onboarding document for new contributors.
- Gated Vercel deployments behind verifications and Supabase migrations in GitHub Actions workflows for dev and prod.
- Cached Supabase Docker for Playwright speed in CI.
- Updated internal tooling for stability.
- Only generate updates in CI.

### Fixed

- Locale validation now works instead of silently failing.
- Request compensation emails now go to the correct recipients.

## 0.3.13 - 2026-05-03

### Added

- Added ability for admins to bulk import submissions without payment, to support pre-launch configuration (#97).
- Added feedback when emails are sent, so scholars know the effect of their actions.
- Added creation date to submissions table and made it sortable.

### Changed

- Updated internal tooling for stability.
- We encourage and account for non-paying authors to be listed (#98).
- Expanded submission visibility in RLS rule to role approvers.
- Improved rendering of emojis in scholar links.
- Improved layout of the reviewer table on the submissions page.
- Improved volunteer status labeling in submission page.

### Fixed

- Don't show bid buttons if a scholar already has the role (#99).
- Hardened `SubmissionLink` to missing submissions to avoid page crashes.
- Consistent visibility of bids on submissions list and submission page.
- Improved logic for "bidding closed" note on submissions page.
- Bid counts now exclude approved bids.

## 0.3.12 - 2026-04-26

### Added

- End-to-end test for new multi-author submissions.
- End-to-end test for volunteering for a reviewing role.
- Included unapproved transactions in scholar task list.

### Changed

- Updated visual design of dashboard to improve navigation and accessibility (#84).
- Removed edge functions from Playwright tests for speed and less flakiness, as we do not have end-to-end tests for that functionality.
- Added caching to Playwright tests for speed.
- Added a minimal CLAUDE.md to specifiy architecture and stack for Claude Code use.
- Approve new submission transaction for submitting author immediately.
- Added another author with tokens in the seed.sql file for testing.

### Fixed

- Fixed text below volunteer header (#90).
- Fixed re-ordering of roles in venue settings (#91).
- Fixed error in inactive venue localization string rendering (#92).
- Corrected spacing below inactive feedback, before page content.
- Fixed issue where transaction approval always mint tokens, instead of only doing so for venue sources.
- Fixed bug preventing author submitting on behalf of co-authors.
- Reset check balances button when payments change on new submission form.

## 0.3.11 - 2026-04-19

### Added

- The new submission page now looks up scholars by ORCID ID, to help authors verify they have the right ORCID.

### Changed

- Updated internal tooling for stability.
- Removed some unused locale strings.
- Improved the visual design of all components for consistency and usability.
- Fully localized the new submission page.
- Lowercased English labels for consistency.
- Fixed invalid HTML caused by markdown wrapped in paragraphs.
- Moved the header and details into the nav bar, to persist while scrolling.
- Redirect to a submission's page after creating a submission.

### Fixed

- Prevented non-authors from attempting to create a submission.
- Fixed submission type on the submission page.
- Submit forms on enter.

## 0.3.10 - 2026-04-05

### Added

- Added gentle reminders to new volunteers to update their name and status.

### Fixed

- Fixed a problem where new volunteer tokens were not minting or transferring correctly to the volunteer.

### Changed

- Updated internal tooling for stability.
- Updated SvelteKit auth approach with Supabase to avoid session security vulnerabilities (#71).
- Removed redundant breadcrumbs to venues and home page.
- Improved styling of feedback.
- Improved font sizes.
- Organized locale files for future translation.
- Made volunteers visible without login.
- Improved visibility and explanation of role volunteering.

## 0.3.9 - 2026-03-29

### Changed

- Updated internal tooling for stability.
- Localized card toggle, tokens component, all paragraph text, and other lingering fallback and default text. Localization should be complete.

## 0.3.8 - 2026-03-22

### Changed

- Updated internal tooling for stability.
- Localized all buttons, text fields, notes, cards, sliders, drop downs, tables, and page headers.

## 0.3.7 - 2026-03-15

### Added

- Implemented localization support and extracted many strings to a default English locale().

### Changed

- Updated internal tooling for stability and speed.
- Improved page header styling and spacing.
- Merged breadcrumbs in page header.
- Improved setup instructions.
- Allow some sliders to not fire immediately, especially if they hit the database.

## 0.3.6 - 2026-03-08

### Added

- Added an updates page to mirror changelog content (#81).
- We now record transactions when tokens are minted on a currency, for transparency.
- Added basic coverage of end-to-end tests for all routes and authentication states (#49).

### Fixed

- Corrected permissions on several table security settings.

## 0.3.5 - 2026-03-01

### Added

- Added pagination to transaction pages for scalability (#72).
- Added emoji icons to page headers for consistency and distinguishability.
- Styled debits in transaction for visibility.
- More tests of the authenticated scholar profile.

### Fixed

- Corrected volunteer count on venue page.

### Changed

- More consistent rendering and phrasing of transactions.
- Better page and header padding.
- Improved header styles.
- Fixed venue link.
- Updated minor versions of Svelte and Supabase.

## 0.3.4 - 2026-02-22

### Added

- Added a submission type and compensation rate by submission type to allow for compensation rates to vary.

### Changed

- Updated prod landing page to add a bit more info about the platform.
- Updated minor versions of `@supabase/supbase-js`, `@sveltjs/kit`, `prettier-plugin-svelte`, `supabase`, `svelte`, `svelte-check`.

## 0.3.3 - 2026-02-15

### Added

- Added tests for `/currency/[id]`, `/curency/[id]/transactions`, `/scholar/[id]/transactions` pages.

### Changed

- Updated minor versions of `@sveltejs/kit`, `svelte`, `svelte-check`, and `supabase`.
- Updated seed to have more tokens for testing.
- Improved display of scholar tokens.
- Improved layout of footer.

### Fixed

- Fixed page margins.

## 0.3.2 - 2026-02-08

### Added

- Added a sticky footer for less frequently used site-wide information and links.
- Make staging and deployment runs dependent on test workflows.
- Added tests for `/`, `/about`, `/scholar/[id]` pages, as well as some utility functions for logging in and out of seeded scholars.

### Changed

- Updated minor versions of `@playright/test`, `@sveltejs/kit`, `supabase`, `svelte`, `@supabase/supabase-js`

## 0.3.1 - 2026-02-01

### Added

- Differentiated between venue admins and editor role, to ensure confidentiality, manage conflicts, and enable compensation (#73).
- Made volunteering public on a scholar's profile page (#76).
- Realtime updates on all schoar, currency, venue, submission, and proposals pages (#26).

### Fixed

- Support creating a new currency in a venue proposal (#74).
- Improved layout of volunteers table (#77).
- Editable text no longer grows the page unbounded (#75).
- Fixed submissions update RLS role to allow editors to edit.
- Better spacing in page metadata.
- Improved spacing of editable text in flex layouts.

### Changed

- Updated minor versions of `supabase/supabase-js`, `@playright/test`, `@sveltejs/adapter-vercel`, `@svelte/kit`, `prettier`, `supabase`, `svelte`, `svelte-check`, and `vitest`.

## 0.3.0 - 2026-01-25

### Added

- Fixed #54, adding anonymity and conflicts support to venues and roles, to implement double anonymous, single anonymous, and open reviewing.
- Added venue active/inactive switch, to allow for venues to be created without being availabe for use yet.
- Created editor-guarded settings page to organize venue settings and declutter landing page.

### Fixed

- Eliminated redundant error `Note`s, merging them with `Feedback`.
- Narrowed a few RLS policies to prevent unauthenticated inserts and updates.
- Fixed logic of assignment approval on submissions page.

## 0.2.2 - 2026-01-18

### Added

- Fixed #69, properly filtering submissions based on role bidding status, assignment status, and total desired assignments.
- Improved saved feedback.

### Fixed

- Clarified meaning of invite and bid.

### Changed

- Updated minor versions of `svelte`, `@sveltejs/kit`, `prettier`, `supabase`, `vitest`.

## 0.2.1 - 2026-01-11

### Added

- Fixed #33: Added volunteer export feature.

### Changed

- Updated minor versions of `@sveltejs`, `supabase`, `@supabase/superbase-js`, `vite`, `vitest` and related dependencies.

## 0.2.0 - 2025-12-14

### Added

- Added approved, incomplete submission assignments to task list.
- Added pending assignment approval task to scholar task list.

### Fixed

- Fixed submission assignment visibility.
- Fixed assignment insertion permissions.
- Improved usability of scholar charge interface on submission page.

### Changed

- Updated minor versions of `@supabase/supabase-js`, `supabase`, `@sveltejs/kit`, `svelte`, `vite`.

## 0.1.9 - 2025-12-07

### Added

- Added volunteer note to landing page.
- Added a theory of change to the about page.
- Fixed #68: Request compensation for role.

### Fixed

- Resolved Svelte stale reference warnings.
- Improved collapsed state of venue editor view.

### Changed

- Updated minor versions of `@playwright/test`, `@supabase/ssr`, `@supabase/supabase-js`, `@sveltejs/adapter-vercel`, `@sveltejs/kit`, `prettier`, `supabase`, `svelte`, `vite`, `vitest`.

## 0.1.8 - 2025-11-28

### Fixed

- Improved and simplified landing page explanation.
- Flipped proposed and active venues on venues page.

## 0.1.7 - 2025-11-23

### Added

- Fixed #53: Migrated to declarative schemas for clarity.

### Fixed

- Linked error message prompts to log in.
- Expand editing roles by default to make volunteering more obvious.
- Less intense token color.

### Changed

- Updated minor versions of Supabase, supabase-js, Svelte, SvelteKit, svelte-check, vitest.

## 0.1.6 - 2025-11-03

### Added

- Fixed #58: Send reminders to editors and scholars to approve proposed transactions.
- Fixed #50: Warning on changing roles with volunteers.

### Fixed

- Fixed #43: Better feedback about unapproved transactions; better link to transactions.
- Improved visual design of forms and text fields.

### Changed

- Updated minor versions of Supabase, Svelte, vite, vitest.

## 0.1.5 - 2025-11-02

### Fixed

- Fixed #63, granting welcome tokens on volunteer assignment or invite accept.
- Improved names of venue proposal functions.
- Fixed #30, preventing editors from being minters of a venue's currency.
- Fixed #66, permit gifting venue.
- Made currency visible to venue viewers.

### Changed

- Updated minor dependencies: Supabase, Svelte, SvelteKit, vitest.

## 0.1.4 - 2025-10-26

### Added

- Better tip styling.
- Consistent currency link styling.
- Better external link styling.
- Show minting roles in profile.
- Added task list to scholar page to show pending invitations and transactions.

### Fixed

- Fixed inline padding of lists.
- Improved save feedback visual design.

### Changed

- Sync SvelteKit types before building in Playwright GitHub Action.
- Slim Playwright browsers tested.
- Updated minor dependencies: supabase, @supabase/supabase-js, @sveltejs/kit, svelte, vite
- Upgraded to vite 4

## 0.1.3 - 2025-10-19

### Changed

- Updated Vercel adapter to 7.0.
- Updated minor dependencies: Playwright, Supabase, SvelteKit, Svelte, Typescirpt, vite

## 0.1.26 - 2025-09-21

### Added

- All manual addition and removal of assignments to submission.
- Fixed #61, compensating roles for completed assignment. Added manual button and CRUD for other contexts.

### Changed

- Updated minor versions of Svelte, SvelteKit, vite.

## 0.1.25 - 2025-09-14

### Fixed

- Distinguished visual design of feedback component from tags.

### Changed

- Updated minor versions of Supabase, Svelte, SvelteKit, Vite.

## 0.1.24 - 2025-09-07

### Fixed

- Refined visual design based on new dashboard/header/card motif.

### Changed

- Updated minor versions of Svelte, Supabase.

## 0.1.23 - 2025-09-01

### Added

- Added a dashboard for high value information on each page, where relevant.
- Started a minor visual motif redesign using a dashboard-metaphor on each page.

### Fixed

- Improved editable text ruler sizing.

### Changed

- Updated minor versions of Supabase, Svelte, Vite.

## 0.1.22 - 2025-08-23

### Added

- Fixed [#29](https://github.com/reciprocalreviews/reciprocalapp/issues/29), adding volunteer filter.
- Fixed [#32](https://github.com/reciprocalreviews/reciprocalapp/issues/23), supporting ORCID for role invites.

### Fixed

- Wrap token formatted text.
- Improved formatting of inline feedback.
- Improved layout of login form.
- Centered save feedback in header.
- Clarified description of minter role.
- Max width on drop downs.
- Properly style error messages.
- Fixed [#52](https://github.com/reciprocalreviews/reciprocalapp/issues/52), minting welcome tokens before granting them.
- Fixed font on non-emoji icons in cards.
- Fixed [#21](https://github.com/reciprocalreviews/reciprocalapp/issues/21), passing session to auth state to prevent page flickering.
- Fixed [#23](https://github.com/reciprocalreviews/reciprocalapp/issues/23), showing editor roles correctly in profile page.
- Restructured list of volunteer roles.

### Changed

- Updated minor versions of Playwright, Supabase, SvelteKit, vite.

## 0.1.21 - 2025-08-16

### Added

- Permit zero submission cost and submissions (also to ease testing of submission creation).
- Fixed #45: Sorting and filtering submissions.
- Fixed #28: Moved invitations to scholar page.
- Send email notification to scholars when invited to a role.

### Fixed

- Improved wrapping of editable text widget.
- Fixed post-submission behavior, collapsing and resetting form.
- Improved padding of cards.
- Better spacing on h1 headers in page.
- Improved venue landing page layout.
- Handle no submissions visible on venue landing page.

### Changed

- Updated minor versions of Svelte, vite, Supabase.

## 0.1.20 - 2025-08-10

### Added

- #31: Dynamic steward list.

### Fixed

- More consistent formatting of currency links.

### Changed

- Updated minor versions of Playwright, Supabase, Svelte, SvelteKit, Typescript, vite.

## 0.1.19 - 2025-07-27

### Changed

- Updated minor versions of Playwright, Supabase, Svelte, SvelteKit, eslint.
- Updated to vite 7.

## 0.1.18 - 2025-06-22

### Fixed

- Type error in error handling.
- Fixed #44: Reminding scholars of stale status.

### Changed

- Updated Playwright, Svelte, SvelteKit, Supabase, eslint.

## 0.1.17 - 2025-06-08

### Added

- Fixed #38, notify stewards of new venue proposal.
- Fixed #36, notify scholars of when they are added or removed to a submission.
- Fixed #39, notify editors of a new venue proposal.

### Fixed

- Typo in editor compensation.
- Resolved all `search_path` security warnings.
- More efficent calls to `auth.uid()` in RLS policies.
- Narrow RLS permissions on submissions delete to authenticated scholars.
- Corrected table for email RLS policy.

### Changed

- Updated Supabase, Svelte, SvelteKit, eslint, vitest.

## 0.1.16 - 2025-05-25

### Added

- Fixed #37, notifying editors and proposers of approved venue.

### Changed

- Updated Supabase, sveltKit, Svelte, Vitest.
- Filtered Chrome log in local development.

## 0.1.15 - 2025-05-18

### Added

- Emails table with trigger that calls Resend edge function to send email.

### Changed

- Updated Svelte, SvelteKit, Eslint, Prettier, Supabase, Vite, Vitest.

## 0.1.14 - 2025-04-20

### Added

- Created a Supabase Edge Function and client-side API for sending an email via Resend.

### Changed

- Updated Playwright, Svelte, SveltKit, Vite, eslint.

## 0.1.13 - 2025-04-13

### Added

- Added bidding scholar balance to submission bidding table.
- Fixed #51 sticky header.
- Saving feedback in sticky header.

### Changed

- Updated Svelte, SvelteKit, Supabase, Supabase SSR, and other minor versions.

## 0.1.12 - 2025-03-23

### Fixed

- Better link to issues page.
- Supress false positive warning.
- Mirrored front and back end submissions visibility.
- Improved layout of submissions table.
- Deactivate button while completing it's action.
- Fixed ordering of roles.
- Keep transactions confidential on submissions page.
- Handle undefined on new role.
- Improved visual design of assignments for submission.
- Verified read and write permissions on submission page.

### Changed

- Updated minor versions of Playwright, Supabase SSR, Svelte, SvelteKit, Eslint, Vitest.

## 0.1.11 - 2025-03-09

### Added

- Added `approve` field to role, defining what other roles can approve bids for assignments to the role.
- Feedback on empty volunteer list.
- Better feedback on role invite success.
- List the number of volunteers in a role on the venue page.

### Fixed

- Improved error handling on role invite form.
- Fixed emoji rendering on Safari.
- Made role invitations more visible.
- Better layout of commitments.
- Improved status tip.
- Improved invitation feedback.

### Changed

- Updated minor versions of Supabase, SvelteKit, Svelte, Vite.
- Ensure SvelteKit is synced upon build, to clearing warning in Vercel builds.

## 0.1.10 - 2025-03-09

### Added

- Show expertise in list of bids on paper.
- Sortable venue roles, to determine presentation order.
- Fixed #24, redesigning venue page to integrate roles.
- Split volunteers page by role, in role order.
- Improved volunteers breadcrumbs.
- Fixed #40, adding editor compensation amount to venue table.

### Fixed

- Distinguished between a assignment bid and an approved assignment, to remember buds if someone is unassigned.
- Improved design of feedback in flex layouts.
- Align table header cells to bottom.
- Full width tables.
- Improved layout and bidding options in submission row.
- Show label on editable text when not editing.
- Make volunteers visible to non-authenticated scholars.

### Changed

- Updated minor versions of Playright, Svelte, SvelteKit, Vite, Vitest.

## 0.1.9 - 2025-03-02

### Fixed

- Account for empty previous id in submission.
- A bit of assignment and volunteering restructuring to better support requirements.

### Changed

- Updated minor versions of Supabase, Svelte, Typescript, Vite.

## 0.1.8 - 2025-02-23

### Added

- Show transactions pending on submissions page.
- Show transactions status on submission page.
- Added a toggleable submission status to each submission, to mark when it is no longer in review.
- Show submissions on scholar page.
- Transaction approval by giver or minter.
- Transaction cancelation by giver, editor, or minter.

### Fixed

- Use Noto Emoji instead of system default to guarantee monochrome, consistent emojis.
- Improved tip visual design.
- Fixed checkbox label alignment.
- Generate proposed transactions for submission.
- Account for currency in gifting and transfers.

### Changed

- Updated minor versions of Svelte, Vite, Vitest.

## 0.1.7 - 2025-02-18

### Added

- More consistent, precise, and type-safe error handling.
- Added transaction IDs to submission to keep track of charges.

### Fixed

- Fixed scholar transactions breadcrumb link.
- Collapse new submission form after submitting.

### Changed

- Updated all minor versions of Supabase, Svelte, SvelteKit.

## 0.1.6 - 2025-02-09

### Added

- Added basic bidding interface.

### Changed

- Updated all minor versions of vite, Typescript, Svelte, Supabase.

## 0.1.5 - 2025-02-02

### Added

- Edit submission title.
- Edit titles in place.
- Added link to previous manuscript submission.

### Fixed

- Resolved several defects with the new submission form.

### Changed

- Updated minor versions of all dependencies.

## 0.1.4 - 2025-01-19

### Added

- Implemented manual submission creation form.
- Styled submission list.
- Added breadcrumbs on all pages to streamline navigation.
- Defined a page to display a submission to authors or editors.

### Changed

- Updated all minor versions of vite, Typescript, Svelte, Supabase.

## 0.1.3 - 2025-01-12

### Added

- Initial progress on `submissions` schema.

### Changed

- Updated all minor versions of vite, Typescript, Svelte, Supabase.

## 0.1.2 - 2024-12-29

### Added

- Improved styling of expandable cards.

### Changed

- Updated all minor versions of dependencies, including Svelte, SvelteKit, and Vite.

## 0.1.1 - 2024-12-08

### Added

- When scholars volunteer for a venue for the first time, create a proposed transaction request for minter to approve, and allow minters to approve it, generating tokens and transferring them to the scholar.

### Fixed

- Redesigned cards to be collapsible, to simplify initial view, make data salient, and convey purpose.

## 0.1.0 - 2024-12-01

### Fixed

- Fixed RLS policy for volunteer insertion.

### Added

- Allow scholars to gift tokens.
- Added pattern for explicit success feedback.

### Changed

- Updated all minor releases of dependencies.
- Updated to vite 6.

## 0.0.10 - 2024-11-17

### Added

- Added number of tokens minted for a currency to the currency page.
- Show number of tokens possed by a venue.
- Show scholar's token count.
- Show scholar's transactions.
- Show venue's transactions.
- Show currency's transactions.
- Added approval status to transactions and updated security rules accordingly.
- Minters mint tokens.
- Venues can gift tokens to scholars.

### Changed

- Updated Svelte and Supabase point releases.

## 0.0.9 - 2024-11-10

### Added

- Defined tokens and transactions table and draft security rules.
- List venues using a currency.
- List minters on a currency.
- Add and remove minters from currency.

### Changed

- Renamed SourceLink to VenueLink for consistency.
- Upgraded Svelte, SvelteKit, Supabase dependencies.

## 0.0.8 - 2024-11-03

### Added

- Added ability to volunteer for a role and set expertise.
- Added ability to stop volunteering for a role.
- Added ability to invite scholars to roles and for scholars to accept and decline roles.
- Added list of volunteer roles to profile.
- Added list of venue volunteers.

### Fixed

- Fixed venues link on home page.

### Changed

- Upgraded Svelte, eslint, and dependencies.

## 0.0.7 - 2024-10-20

### Added

- Venue page: currency link, welcome amount, bidding toggle, role creation, editing, and deletion.

### Fixed

- A few typography improvements.
- Deactivated hover feedback on inactive buttons.
- Fixed rendering for missing name in venue proposal.

### Changed

- Upgraded to Svelte 5.0.

## 0.0.6 - 2024-10-13

### Added

- Subtitles for pages, with more consistent display.
- Edit and delete support for a venue proposal.
- Stewards can edit, delete, and approve a venue proposal.
- List active venues.
- Display venue title, description, and link.
- Edit venue editors, title, and URL.

### Fixed

- Corrected automatic height on text areas.

## 0.0.5 - 2024-10-06

### Added

- Currency name and description display and editing.
- Show proposed venues on the venues page.
- Render proposed venue content.
- Allow additional support to a proposal.

## 0.0.4 - 2024-09-28

### Added

- Visual design polish on components.
- Added accessible notifications section.
- Create currencies and exchanges.
- Create currency route.

### Changed

- Updated Svelte and Supabase minor versions.
- Updated GitHub checkout action dependencies.

## 0.0.3 - 2024-09-01

### Changed

- Updated Svelte and Supabase minor revisions.

## 0.0.2 - 2024-08-25

### Added

- Supabase scripts for documentation.
- Basic email one-time password authenatication.

### Changed

- Updated Svelte and Supabase minor revisions
- Migrated auth state to Svelte state class.

## 0.0.1 - 2024-08-04

### Added

- Created CHANGELOG.
- Custom favicon.
- Set up GitHub actions for unit and integration tests.
- Configured Supabase, including continuous integration on `dev` and `main` branches to `reciprocal-staging` and `reciprocal-production`, respectively.
- Added basic OTP authentication for dev purposes.

### Updated

- typescript, vite, vitest, svelte, prettier, playwright
