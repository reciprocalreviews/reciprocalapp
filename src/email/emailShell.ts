// The branded email shell lives beside the edge functions
// (supabase/functions/_shared/emailShell.ts) because, like the template registry it
// wraps, it is applied at SEND time by the `resend` function rather than by the caller.
// Deno only bundles files under supabase/functions, hence the location.
//
// Re-exported here so application code — and the unit tests, which vitest only collects
// from `src/**/*.unit.ts` — import it from one place. Mirrors ./templates.ts.
export * from '../../supabase/functions/_shared/emailShell';
