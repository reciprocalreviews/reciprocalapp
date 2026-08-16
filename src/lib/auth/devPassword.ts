/** The password every seeded user shares on a local stack.
 *
 * `supabase/seed.sql` sets it for all of them in one statement, so it is not a
 * secret and never leaves local development: the password grant only exists
 * against a local Supabase, and these accounts exist nowhere else.
 *
 * Shared by the local sign-in list on the login page and by the Playwright
 * helper (`src/routes/login.ts`), so the two cannot drift apart. It lives here
 * rather than in that helper because the helper imports `@playwright/test`, and
 * the application must not pull test code into its bundle to learn one string.
 */
export const SEED_PASSWORD = 'password';
