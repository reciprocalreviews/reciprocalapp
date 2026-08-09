-- Re-apply every recorded erasure. MANDATORY after any restore.
--
--     DB_URL=... ./supabase/dr/psql.sh -f supabase/dr/reapply-erasures.sql
--
-- A backup taken before someone asked to be forgotten still contains them.
-- Restoring it brings them back, and the platform is then holding data it told
-- that person it had destroyed — a broken promise created by the recovery itself,
-- and one nobody would notice.
--
-- public.erasures exists precisely so that list survives the restore and can be
-- replayed over it. It has no foreign key to scholars, so it stays valid even
-- against a restore that predates the accounts it names.
--
-- Safe to run repeatedly: forget_scholar only ever removes, so applying it twice
-- to an already-anonymous row changes nothing.
\set ON_ERROR_STOP on

do $$
declare
	_e record;
	_n int := 0;
	_missing int := 0;
begin
	for _e in select subject from public.erasures order by requested_at loop
		if exists (select 1 from public.scholars where id = _e.subject) then
			perform public.forget_scholar(_e.subject);
			_n := _n + 1;
		else
			-- The person is not in this restore at all, which is fine: nothing to
			-- erase. Counted so a surprising number is visible rather than silent.
			_missing := _missing + 1;
		end if;
	end loop;
	raise notice 're-applied % erasure(s); % subject(s) absent from this restore', _n, _missing;
end;
$$;

select
	count(*) filter (
		where
			completed_at is not null
	) as completed,
	count(*) as recorded
from
	public.erasures;
