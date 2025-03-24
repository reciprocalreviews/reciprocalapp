# Changes

Hi! This is where we document all notable changes, including bug fixes, enhancements, and dependency updates.
Dates should be in`YYYY-MM-DD` format and versions are in [semantic versioning](http://semver.org/) format.

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

### Maintenance

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

### Maintenance

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

### Maintenance

- Updated minor versions of Playright, Svelte, SvelteKit, Vite, Vitest.

## 0.1.9 2025-03-02

### Fixed

- Account for empty previous id in submission.
- A bit of assignment and volunteering restructuring to better support requirements.

### Maintenance

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

### Maintenance

- Updated minor versions of Svelte, Vite, Vitest.

## 0.1.7 2025-02-18

### Added

- More consistent, precise, and type-safe error handling.
- Added transaction IDs to submission to keep track of charges.

### Fixed

- Fixed scholar transactions breadcrumb link.
- Collapse new submission form after submitting.

### Maintenance

- Updated all minor versions of Supabase, Svelte, SvelteKit.

## 0.1.6 2025-02-09

### Added

- Added basic bidding interface.

### Maintenance

- Updated all minor versions of vite, Typescript, Svelte, Supabase.

## 0.1.5 2025-02-02

### Added

- Edit submission title.
- Edit titles in place.
- Added link to previous manuscript submission.

### Fixed

- Resolved several defects with the new submission form.

### Maintenance

- Updated minor versions of all dependencies.

## 0.1.4 2025-01-19

### Added

- Implemented manual submission creation form.
- Styled submission list.
- Added breadcrumbs on all pages to streamline navigation.
- Defined a page to display a submission to authors or editors.

### Maintenance

- Updated all minor versions of vite, Typescript, Svelte, Supabase.

## 0.1.3 2025-01-12

### Added

- Initial progress on `submissions` schema.

### Maintenance

- Updated all minor versions of vite, Typescript, Svelte, Supabase.

## 0.1.2 2024-12-29

### Added

- Improved styling of expandable cards.

### Maintenance

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

### Maintenance

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

### Maintenance

- Updated Svelte and Supabase point releases.

## 0.0.9 2024-11-10

### Added

- Defined tokens and transactions table and draft security rules.
- List venues using a currency.
- List minters on a currency.
- Add and remove minters from currency.

### Maintenance

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

### Maintenance

- Upgraded Svelte, eslint, and dependencies.

## 0.0.7 2024-10-20

### Added

- Venue page: currency link, welcome amount, bidding toggle, role creation, editing, and deletion.

### Fixed

- A few typography improvements.
- Deactivated hover feedback on inactive buttons.
- Fixed rendering for missing name in venue proposal.

### Maintenance

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

### Maintenance

- Updated Svelte and Supabase minor versions.
- Updated GitHub checkout action dependencies.

## 0.0.3 2024-09-01

### Maintenance

- Updated Svelte and Supabase minor revisions.

## 0.0.2 2024-08-25

### Added

- Supabase scripts for documentation.
- Basic email one-time password authenatication.

### Maintenance

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
