-- Restrict which columns of public.scholars a scholar may write.
--
-- The "Scholars can be edited by stewards and selves" policy authorizes the ROW but says
-- nothing about columns, and `grant all` handed authenticated a table-wide UPDATE. A
-- scholar could therefore write any column of their own row through PostgREST:
--
--   * `steward`  — privilege escalation: self-promotion to platform steward.
--   * `orcid`    — the identity anchor (#19/#87). Rewriting it means claiming another
--                  researcher's iD, which is exactly the ambiguity ORCID auth removes.
--   * `email`    — bypasses contact-email verification entirely (#27), defeating the
--                  invariant that scholars.email only ever holds a VERIFIED address.
--
-- As established in 20260601000000_rls_corrections.sql, a column-level revoke is a no-op
-- while the table-level UPDATE from `grant all` stands, so drop that first and re-grant
-- only the columns a scholar legitimately edits about themselves. `email` is written
-- solely by public.verify_email, and `status_reminder_time` solely by the remind edge
-- function — both run with privileges that bypass these grants.
--
-- Note that column grants are role-wide, so this narrows stewards too (they are also
-- `authenticated`). That is intended: nothing in the app edits another scholar's email,
-- orcid, or steward flag, and a future steward tool for that belongs behind a
-- SECURITY DEFINER RPC gated on isSteward(), not a blanket table privilege.

revoke
update on public.scholars
from
	authenticated,
	anon;

grant
update (name, available, status, status_time) on public.scholars to authenticated;

-- One ORCID iD identifies exactly one scholar. Partial, because a scholar row created
-- outside the ORCID flow (tests, fixtures) may legitimately have no iD yet.
create unique index if not exists scholars_orcid_unique on public.scholars (orcid)
where
	orcid is not null;
