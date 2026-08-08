-- Make the append-only tables append-only for service_role too.
--
-- token_events, audit_log, and reconciliations each say, in their own comments,
-- that service_role gets SELECT. Each then only ever ran `grant select`, which
-- adds a privilege without removing any — and Supabase's default privileges have
-- already granted service_role ALL on every new table in `public` by the time the
-- grant runs. So all three have carried INSERT, UPDATE, and DELETE for
-- service_role since the day they were created, directly contradicting the
-- comment above the grant.
--
-- Found by the schema-drift check rather than by reading: the declarative files
-- and the migrations produced databases that differed here, and chasing why
-- surfaced the gap between what the grant said and what it did. The same shape as
-- the tokens hole in 20260802010000 — `grant all` conferring more than the
-- narrower grant beneath it implies.
--
-- Little changes in practice: the append-only triggers already refuse UPDATE and
-- DELETE from every role, and every legitimate write comes from a SECURITY
-- DEFINER function owned by postgres, which is unaffected by role grants. This
-- closes the gap between the stated model and the enforced one, so a reader can
-- trust the grant.
revoke insert,
update,
delete on table public.token_events
from
	service_role;

revoke insert,
update,
delete on table public.audit_log
from
	service_role;

-- reconciliations is monitoring output rather than evidence, but there is no
-- reason for service_role to write it either: reconcile_ledger() is SECURITY
-- DEFINER and inserts as the owner.
revoke insert,
update,
delete on table public.reconciliations
from
	service_role;
