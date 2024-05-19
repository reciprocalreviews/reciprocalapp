> [!WARNING]  
> The architecture is in flux, as the design is still in flux. We'll try to keep this guide up to date as it stabilizes.

# Architecture

Recirocal Reviews is a web application. It has a **front end** that reviewers, authors, and editors use to track their tokens and a **back end** that manages data and noticiations.

We have not finalized a stack yet, but we are considering:

- [Svelte](https://svelte.dev/) for it's low-boilerplate, high-speed interfaces
- [SvelteKit](https://kit.svelte.dev/) for it's integration with Svelte and elegant reuse opportunities across server and client
- [Vercel](https://vercel.com) for hosting and tight integration with SvelteKit
- [Supabase](https://supabase.com/) for it's streamlined, open source support for Postgres database management

# Key source

There are several key sources for the implementation:

- `src/lib`. This is where reusable Svelte components live.
- `src/routes`. This is where web page end points and data retrieval live. See the SvelteKit documentation for how routes work.
- `static`. This is where assets live.
