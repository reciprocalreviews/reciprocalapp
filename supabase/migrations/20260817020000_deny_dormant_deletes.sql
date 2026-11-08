-- Deny the dormant DELETE paths on venues, currencies, and submissions.
--
-- Three DELETE policies granted deletion to stewards/admins/minters, but no UI
-- and no CRUD method ever calls them — the only way to exercise them was a
-- hand-crafted PostgREST request from a browser console with a user JWT. What
-- they permitted was severe: deleting a venue cascades away its roles,
-- volunteers, assignments, compensation, preference levels, and thanks
-- (blocked only accidentally, by the money tables' plain FKs), and deleting a
-- submission destroys its assignment history. Following the tokens/transactions
-- pattern, the table privilege is revoked AND an explicit deny policy documents
-- the intent so the pgTAP suite can assert it. service_role is untouched, so
-- administrative surgery during an incident still has a path.

drop policy "stewards and admins can delete venues" on public.venues;

create policy "venues cannot be deleted" on public.venues for DELETE to authenticated using (false);

revoke delete on public.venues
from
	authenticated,
	anon;

drop policy "minters can delete currencies" on "public"."currencies";

create policy "currencies cannot be deleted" on public.currencies for DELETE to authenticated using (false);

revoke delete on public.currencies
from
	authenticated,
	anon;

drop policy "admins can delete submissions" on public.submissions;

create policy "submissions cannot be deleted" on public.submissions for DELETE to authenticated using (false);

revoke delete on public.submissions
from
	authenticated,
	anon;
