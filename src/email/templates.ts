// The email template registry lives beside the edge functions
// (supabase/functions/_shared/templates.ts) because it is rendered at SEND time by the
// `resend` function rather than by the caller: an email whose recipient is chosen by the
// caller must not also have its body chosen by the caller, or the pipeline is an open
// relay. Deno only bundles files under supabase/functions, hence the location.
//
// Re-exported here so application code keeps importing it from one place.
export * from '../../supabase/functions/_shared/templates';
