-- Manuscript IDs carry no leading or trailing whitespace.
--
-- The "Pay for a submission" form stored the ID exactly as typed, so a space pasted along with
-- it became part of the ID. Every lookup by manuscript ID -- Check payments, compensation
-- requests, predecessor links -- is an exact match on a trimmed ID, so such a submission could
-- not be found: Check payments called a paid submission "not submitted". The client now trims;
-- this repairs the rows already stored and refuses any writer that does not trim.
--
-- No repaired ID collides with an existing one at its venue (checked against production before
-- writing this); if one did, submissions_venue_externalid_unique would stop the migration
-- rather than merge two submissions.

update public.submissions
set
	externalid = regexp_replace(externalid, '^\s+|\s+$', '', 'g')
where
	externalid ~ '^\s|\s$';

alter table public.submissions
add constraint submissions_externalid_trimmed check (externalid !~ '^\s|\s$');
