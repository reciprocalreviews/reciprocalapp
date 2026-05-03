# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
npm run dev          # Start Vite dev server
npm run check:now    # Run svelte-check for TypeScript/Svelte errors
npm run test:unit    # Run Vitest unit tests (src/**/*.unit.ts)
npm run test:end     # Run Playwright integration tests (end2end/)
npm start            # Start Supabase locally + edge functions
npm run reset        # Reset local Supabase DB and regenerate types
npm run types        # Regenerate TypeScript types from Supabase schema
npm run locale       # Validate all locale JSON files against schema
```

## Tech Stack

- **Frontend:** Svelte 5 (runes) + SvelteKit 2, TypeScript strict mode
- **Database/Auth:** Supabase (PostgreSQL + Auth via email/OTP)
- **Hosting:** Vercel via `@sveltejs/adapter-vercel`
- **Testing:** Vitest (unit) + Playwright (integration, Chromium only)
- **Code Style:** Prettier — tabs, single quotes, 100-char lines

## Architecture

### Routing

All routes live under `src/routes/[[lang]]/` — `[[lang]]` is an optional locale prefix (defaults to `en`). Route structure:

- `[[lang]]/login/` — authentication
- `[[lang]]/scholar/[id]/` — scholar profiles
- `[[lang]]/venue/[venueid]/` — venue dashboard, settings, submissions, roles
- `[[lang]]/currency/[id]/` — currency management
- `[[lang]]/venues/proposal/` — new venue proposals

### Data Layer

The database layer is abstracted: `src/lib/data/CRUD.ts` defines the interface; `src/lib/data/SupabaseCRUD.svelte.ts` implements it. The instance is set in the root layout via `setDB(() => crud)` and accessed anywhere via `getDB()`. All operations return `Result<T> = {data?: T, error?: DBError}`. Use the `handle()` helper from `feedback.svelte.ts` to wrap DB calls — it posts error notifications automatically.

### Localization

The locale system works as follows:

1. `src/lib/locales/Locale.ts` defines the `LocaleText` type (source of truth for all strings)
2. `static/locales/en.json` holds the English strings (only locale currently)
3. Root layout loads locale JSON server-side and sets context via `setLocaleContext()`
4. Components access locale via `getLocaleContext()` and pass path functions to `<Text>`

Patterns in use:

```svelte
<!-- Rendering text -->
<Text path={(l) => l.page.login.buttons.login} />

<!-- Component label props -->
<TextField label={(l) => l.page.login.form.email.label} />

<!-- Validation messages -->
valid={(text) => (isNotEmpty(text) ? undefined : (l) => l.page.x.form.y.validation)}
```

After changing `Locale.ts`, run `npm run locale` to regenerate the schema and validate `en.json`.

### Auth

Auth uses Supabase email/OTP. `src/hooks.server.ts` creates a per-request Supabase client from cookies. `getClaims()` validates the JWT locally before any database queries. The auth abstraction is `src/lib/auth/` — don't bypass it to call Supabase directly.

### Global Context

The root layout (`src/routes/+layout.svelte`) sets up four pieces of context consumed throughout the app:

- `setDB()` — database instance
- `setLocaleContext()` — locale strings
- `setFeedback()` — error/success notifications
- `setBreadcrumbs()` / page headers — navigation

### State

Svelte 5 runes (`$state`, `$derived`, `$effect`) are used throughout. Class components (like `SupabaseCRUD`) use `$state` fields. Prefer `$derived` over `$effect` for computed values.

### Email

Emails are sent via Resend in production (triggered by Supabase Edge Functions watching an `emails` table). Locally they log to console. Templates are in `src/email/templates.ts`.
