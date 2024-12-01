# Changes

Hi! This is where we document all notable changes, including bug fixes, enhancements, and dependency updates.
Dates should be in`YYYY-MM-DD` format and versions are in [semantic versioning](http://semver.org/) format.

## 0.0.11 2024-12-1

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
