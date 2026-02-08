# Changes

Hi! This is where we document all notable changes, including bug fixes, enhancements, and dependency updates.
Dates should be in`YYYY-MM-DD` format.

## 0.3.2 2026-02-08

### Added

- Added a sticky footer for less frequently used site-wide information and links.
- Make staging and deployment runs dependent on test workflows.

### Changed

- Updated minor versions of `@playright/test`, `@sveltejs/kit`, `supabase`, `svelte`, `@supabase/supabase-js`

## 0.3.1 2026-02-01

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

## 0.3.0 2026-01-25

### Added

- Fixed #54, adding anonymity and conflicts support to venues and roles, to implement double anonymous, single anonymous, and open reviewing.
- Added venue active/inactive switch, to allow for venues to be created without being availabe for use yet.
- Created editor-guarded settings page to organize venue settings and declutter landing page.

### Fixed

- Eliminated redundant error `Note`s, merging them with `Feedback`.
- Narrowed a few RLS policies to prevent unauthenticated inserts and updates.
- Fixed logic of assignment approval on submissions page.

## 0.2.2 2026-01-18

### Added

- Fixed #69, properly filtering submissions based on role bidding status, assignment status, and total desired assignments.
- Improved saved feedback.

### Fixed

- Clarified meaning of invite and bid.

### Changed

- Updated minor versions of `svelte`, `@sveltejs/kit`, `prettier`, `supabase`, `vitest`.

## 0.2.1 2026-01-11

### Added

- Fixed #33: Added volunteer export feature.

### Changed

- Updated minor versions of `@sveltejs`, `supabase`, `@supabase/superbase-js`, `vite`, `vitest` and related dependencies.

## 0.2.0 2025-12-14

### Added

- Added approved, incomplete submission assignments to task list.
- Added pending assignment approval task to scholar task list.

### Fixed

- Fixed submission assignment visibility.
- Fixed assignment insertion permissions.
- Improved usability of scholar charge interface on submission page.

### Changed

- Updated minor versions of `@supabase/supabase-js`, `supabase`, `@sveltejs/kit`, `svelte`, `vite`.

## 0.1.9 2025-12-07

### Added

- Added volunteer note to landing page.
- Added a theory of change to the about page.
- Fixed #68: Request compensation for role.

### Fixed

- Resolved Svelte stale reference warnings.
- Improved collapsed state of venue editor view.

### Changed

- Updated minor versions of `@playwright/test`, `@supabase/ssr`, `@supabase/supabase-js`, `@sveltejs/adapter-vercel`, `@sveltejs/kit`, `prettier`, `supabase`, `svelte`, `vite`, `vitest`.

## 0.1.8 2025-11-28

### Fixed

- Improved and simplified landing page explanation.
- Flipped proposed and active venues on venues page.

## 0.1.7 2025-11-23

### Added

- Fixed #53: Migrated to declarative schemas for clarity.

### Fixed

- Linked error message prompts to log in.
- Expand editing roles by default to make volunteering more obvious.
- Less intense token color.

### Changed

- Updated minor versions of Supabase, supabase-js, Svelte, SvelteKit, svelte-check, vitest.

## 0.1.6 2025-11-03

### Added

- Fixed #58: Send reminders to editors and scholars to approve proposed transactions.
- Fixed #50: Warning on changing roles with volunteers.

### Fixed

- Fixed #43: Better feedback about unapproved transactions; better link to transactions.
- Improved visual design of forms and text fields.

### Changed

- Updated minor versions of Supabase, Svelte, vite, vitest.

## 0.1.5 2025-11-02

### Fixed

- Fixed #63, granting welcome tokens on volunteer assignment or invite accept.
- Improved names of venue proposal functions.
- Fixed #30, preventing editors from being minters of a venue's currency.
- Fixed #66, permit gifting venue.
- Made currency visible to venue viewers.

### Changed

- Updated minor dependencies: Supabase, Svelte, SvelteKit, vitest.

## 0.1.4 2025-10-26

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

## 0.1.3 2025-10-19

### Changed

- Updated Vercel adapter to 7.0.
- Updated minor dependencies: Playwright, Supabase, SvelteKit, Svelte, Typescirpt, vite

## 0.1.26 2025-09-21

### Added

- All manual addition and removal of assignments to submission.
- Fixed #61, compensating roles for completed assignment. Added manual button and CRUD for other contexts.

### Changed

- Updated minor versions of Svelte, SvelteKit, vite.

## 0.1.25 2025-09-14

### Fixed

- Distinguished visual design of feedback component from tags.

### Changed

- Updated minor versions of Supabase, Svelte, SvelteKit, Vite.

## 0.1.24 2025-09-07

### Fixed

- Refined visual design based on new dashboard/header/card motif.

### Changed

- Updated minor versions of Svelte, Supabase.

## 0.1.23 2025-09-01

### Added

- Added a dashboard for high value information on each page, where relevant.
- Started a minor visual motif redesign using a dashboard-metaphor on each page.

### Fixed

- Improved editable text ruler sizing.

### Changed

- Updated minor versions of Supabase, Svelte, Vite.

## 0.1.22 2025-08-23

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

## 0.1.21 2025-08-16

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

## 0.1.20 2025-08-10

### Added

- #31: Dynamic steward list.

### Fixed

- More consistent formatting of currency links.

### Changed

- Updated minor versions of Playwright, Supabase, Svelte, SvelteKit, Typescript, vite.

## 0.1.19 2025-07-27

### Changed

- Updated minor versions of Playwright, Supabase, Svelte, SvelteKit, eslint.
- Updated to vite 7.

## 0.1.18 2025-06-22

### Fixed

- Type error in error handling.
- Fixed #44: Reminding scholars of stale status.

### Changed

- Updated Playwright, Svelte, SvelteKit, Supabase, eslint.

## 0.1.17 2025-06-08

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

## 0.1.16 2025-05-25

### Added

- Fixed #37, notifying editors and proposers of approved venue.

### Changed

- Updated Supabase, sveltKit, Svelte, Vitest.
- Filtered Chrome log in local development.

## 0.1.15 2025-05-18

### Added

- Emails table with trigger that calls Resend edge function to send email.

### Changed

- Updated Svelte, SvelteKit, Eslint, Prettier, Supabase, Vite, Vitest.

## 0.1.14 2025-04-20

### Added

- Created a Supabase Edge Function and client-side API for sending an email via Resend.

### Changed

- Updated Playwright, Svelte, SveltKit, Vite, eslint.

## 0.1.13 2025-04-13

### Added

- Added bidding scholar balance to submission bidding table.
- Fixed #51 sticky header.
- Saving feedback in sticky header.

### Changed

- Updated Svelte, SvelteKit, Supabase, Supabase SSR, and other minor versions.

## 0.1.12 2025-03-23

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

## 0.1.11 2025-03-09

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

## 0.1.10 2025-03-09

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

## 0.1.9 2025-03-02

### Fixed

- Account for empty previous id in submission.
- A bit of assignment and volunteering restructuring to better support requirements.

### Changed

- Updated minor versions of Supabase, Svelte, Typescript, Vite.

## 0.1.8 2025-02-23

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

## 0.1.7 2025-02-18

### Added

- More consistent, precise, and type-safe error handling.
- Added transaction IDs to submission to keep track of charges.

### Fixed

- Fixed scholar transactions breadcrumb link.
- Collapse new submission form after submitting.

### Changed

- Updated all minor versions of Supabase, Svelte, SvelteKit.

## 0.1.6 2025-02-09

### Added

- Added basic bidding interface.

### Changed

- Updated all minor versions of vite, Typescript, Svelte, Supabase.

## 0.1.5 2025-02-02

### Added

- Edit submission title.
- Edit titles in place.
- Added link to previous manuscript submission.

### Fixed

- Resolved several defects with the new submission form.

### Changed

- Updated minor versions of all dependencies.

## 0.1.4 2025-01-19

### Added

- Implemented manual submission creation form.
- Styled submission list.
- Added breadcrumbs on all pages to streamline navigation.
- Defined a page to display a submission to authors or editors.

### Changed

- Updated all minor versions of vite, Typescript, Svelte, Supabase.

## 0.1.3 2025-01-12

### Added

- Initial progress on `submissions` schema.

### Changed

- Updated all minor versions of vite, Typescript, Svelte, Supabase.

## 0.1.2 2024-12-29

### Added

- Improved styling of expandable cards.

### Changed

- Updated all minor versions of dependencies, including Svelte, SvelteKit, and Vite.

## 0.1.1 2024-12-08

### Added

- When scholars volunteer for a venue for the first time, create a proposed transaction request for minter to approve, and allow minters to approve it, generating tokens and transferring them to the scholar.

### Fixed

- Redesigned cards to be collapsible, to simplify initial view, make data salient, and convey purpose.

## 0.1.0 2024-12-01

### Fixed

- Fixed RLS policy for volunteer insertion.

### Added

- Allow scholars to gift tokens.
- Added pattern for explicit success feedback.

### Changed

- Updated all minor releases of dependencies.
- Updated to vite 6.

## 0.0.10 2024-11-17

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

## 0.0.9 2024-11-10

### Added

- Defined tokens and transactions table and draft security rules.
- List venues using a currency.
- List minters on a currency.
- Add and remove minters from currency.

### Changed

- Renamed SourceLink to VenueLink for consistency.
- Upgraded Svelte, SvelteKit, Supabase dependencies.

## 0.0.8 2024-11-03

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

## 0.0.7 2024-10-20

### Added

- Venue page: currency link, welcome amount, bidding toggle, role creation, editing, and deletion.

### Fixed

- A few typography improvements.
- Deactivated hover feedback on inactive buttons.
- Fixed rendering for missing name in venue proposal.

### Changed

- Upgraded to Svelte 5.0.

## 0.0.6 2024-10-13

### Added

- Subtitles for pages, with more consistent display.
- Edit and delete support for a venue proposal.
- Stewards can edit, delete, and approve a venue proposal.
- List active venues.
- Display venue title, description, and link.
- Edit venue editors, title, and URL.

### Fixed

- Corrected automatic height on text areas.

## 0.0.5 2024-10-06

### Added

- Currency name and description display and editing.
- Show proposed venues on the venues page.
- Render proposed venue content.
- Allow additional support to a proposal.

## 0.0.4 2024-09-28

### Added

- Visual design polish on components.
- Added accessible notifications section.
- Create currencies and exchanges.
- Create currency route.

### Changed

- Updated Svelte and Supabase minor versions.
- Updated GitHub checkout action dependencies.

## 0.0.3 2024-09-01

### Changed

- Updated Svelte and Supabase minor revisions.

## 0.0.2 2024-08-25

### Added

- Supabase scripts for documentation.
- Basic email one-time password authenatication.

### Changed

- Updated Svelte and Supabase minor revisions
- Migrated auth state to Svelte state class.

## 0.0.1 2024-08-04

### Added

- Created CHANGELOG.
- Custom favicon.
- Set up GitHub actions for unit and integration tests.
- Configured Supabase, including continuous integration on `dev` and `main` branches to `reciprocal-staging` and `reciprocal-production`, respectively.
- Added basic OTP authentication for dev purposes.

### Updated

- typescript, vite, vitest, svelte, prettier, playwright
