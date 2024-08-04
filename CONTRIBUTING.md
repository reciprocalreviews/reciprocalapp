# Contributing to Reciprocal Reviews

Welcome to the contributor guide! This document is represents a ground truth for our process; everyone who contributs to the project should follow its guidelines, so read it carefully.

## Getting started

The first and most important thing to do is to understand the motivations for the project. Read the [reciprocal reviews proposal](https://docs.google.com/document/d/1RHirbCdQFxBeCbjAAbba1MJtxDOG4cuml66_xWGgXAI/edit#heading=h.gtlebyp3cvjf) to understand what we're trying to build and why.

Next, read the [design specification](DESIGN.md). This document attempts to articulate the experience of reviewers, editors, and authors, and the functionality that supports it.

Finally, read our [architecture guide](ARCHITECTURE.md), which discusses the key technologies, components, and concepts in the implementation, so you can navigate the implementation.

Finally, if you have questions about anything, join our [Discord](https://discord.gg/GzdCGzWMrj) and ask away. There's almost certainly something important we've missed here, and your questions will help us know what to add.

## Contributing

At the moment, we are happy to accept the following types of contributions:

- [Bug reports and enhancment ideas](https://github.com/reciprocalreviews/reciprocalapp/issues). Before you submit, make sure there isn't an existing issue for what you want to report.
- [Pull requests](https://github.com/reciprocalreviews/reciprocalapp/pulls). Find an unassigned issue, comment on it to see if it's appropriate to work on, and a maintainer will reply and potentially assign you. If they do, fork, work on the issue, and submit a pull request for review and possible merging.

## Stack

We are currently using:

- TypeScript 5
- Svelte 5 and SvelteKit for front end
- Vite for local development
- Vercel for hosting and deployment
- Supabase for data hosting and authentication
- vitest for unit tests
- Playwright for integration tests.

## Branching strategy

On the team, we use a Git Flow continuous integration workflow. That means:

- The currently released production code lives in `main`
- `dev` is the staging branch, automatically released to our public staging server, which lives at [test.reciprocal.reviews](https://test.reciprocal.reviews).
- Feature branches should be created from `dev` and follow this format `issue-description`, where `issue` is a corresponding issue number.

Feature branches should be merged into `dev`, which trigger a release to a staging server on Vercel. And a production release involves merging `dev` into `main`.

Pull requests should fork, branch from `dev`, and target `dev`. One of the maintainers will review, and if accepted, merge to `dev`.

Unit and integration tests will run on merge to `dev` via GitHub actions.

## Local development

The key tools for local development are:

- Vite: run `npm run dev` to launch the Vite local development server, and test at the localhost address provided.
- Svelte check: run `npm run check`, which will report TypeScript and Svelte errors.
- Supabase: run `npm run db` to start the Supabase database locally. This will require installation of a Docker client.
- vitest: run `npm run test:unit` to run unit tests during development.
- Playright: run `npm run test:integration` to run integration tests on demand.
- Supabase CLI: [install](https://supabase.com/docs/guides/cli/getting-started), and then `supabase login`, and then `supabase start` to load the local database with Docker. Don't forget to `supabase stop` when you're done to release Docker resources.

## Tests

- vitest unit tests can live anywhere in `/src` and must end with `test.ts`
- Playwright integration tests live in `/tests`.
