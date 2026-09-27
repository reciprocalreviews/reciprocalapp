// The expertise keyword rule lives beside the edge functions
// (supabase/functions/_shared/expertise.ts), next to the SQL that matches on the same rule for
// the weekly bidding digest. Re-exported here so application code imports it from one place.
// Mirrors ./orcidProfile.ts.
export * from '../../../supabase/functions/_shared/expertise';
