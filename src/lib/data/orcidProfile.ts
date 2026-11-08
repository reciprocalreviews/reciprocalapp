// The ORCID record parser lives beside the edge functions
// (supabase/functions/_shared/orcidProfile.ts) because the `orcid` function is what
// fetches, and Deno only bundles files under supabase/functions.
//
// Re-exported here so application code — and the unit tests, which vitest only collects
// from `src/**/*.unit.ts` — import it from one place. Mirrors src/email/emailShell.ts.
export * from '../../../supabase/functions/_shared/orcidProfile';
