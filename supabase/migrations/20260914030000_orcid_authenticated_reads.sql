-- Authenticated ORCID reads, and the pressure gauge that tells us whether we need them.
--
-- Two changes, both in service of #173:
--
--   1. `fetch_rate_limited_at` records when ORCID last answered a read with 429. Its own
--      column rather than something parsed out of fetch_detail, because `fetch_status =
--      'error'` conflates a 429 with a 500, a timeout and a parse failure -- and only the
--      429 answers "are we exhausting the anonymous daily budget".
--
--   2. The SELECT grant is narrowed to named columns, leaving `fetch_detail` out. Its
--      comment always said it was never rendered to a visitor, but the grant was
--      table-wide, so PostgREST would hand it to anyone who asked. Not rendered and not
--      readable are different things; pending_email_verification omits delivery_detail for
--      the same reason.
--
-- Paired with supabase/schemas/orcid_profiles.sql.

alter table public.orcid_profiles
add column if not exists fetch_rate_limited_at timestamptz;

-- Revoked first: a column-level grant does not narrow anything while a table-wide one
-- stands, exactly as a column-level REVOKE is a no-op under `grant all` (see
-- 20260601000000_rls_corrections.sql). The table grant has to go before the column list
-- means anything.
revoke
select
	on table public.orcid_profiles
from
	anon,
	authenticated;

grant
select
	(
		scholar,
		orcid,
		employment_role,
		employment_department,
		employment_organization,
		education_role,
		education_organization,
		education_year,
		keywords,
		works,
		work_count,
		work_first_year,
		work_last_year,
		links,
		fetched_at,
		works_fetched_at,
		fetch_attempted_at,
		fetch_status,
		fetch_failures,
		fetch_rate_limited_at
	) on table public.orcid_profiles to anon,
	authenticated;

--------------------------------------
-- Mirror health, for the steward card.
/**
 * How the mirror is doing, for a steward deciding whether it needs attention.
 *
 * The counts exist because `fetch_status = 'error'` cannot answer the only operational
 * question there is: a 429 means we are exhausting ORCID's anonymous daily budget and should
 * register an API client (#173), while a 500 or a timeout means ORCID had a bad minute and
 * the backoff will handle it. They are different problems with different responses, and the
 * status column alone conflates them.
 *
 * Steward-gated to match the card that renders it, not because the numbers are secret --
 * `orcid_profiles` is world-readable and anyone could count these rows themselves. It is an
 * operational view, and it belongs where the other operational controls are.
 */
create or replace function public.orcid_mirror_health () returns jsonb language plpgsql security definer
set
	search_path = '' as $$
declare
	_result jsonb;
begin
	if not public.isSteward() then
		raise exception 'Only a steward can read ORCID mirror health' using errcode = 'RR006';
	end if;

	select jsonb_build_object(
		-- The denominator: scholars who HAVE an iD, so an erased tombstone or a seeded
		-- fixture is not counted as a profile we are failing to read.
		'scholars', count(*) filter (where s.orcid is not null),
		'read', count(*) filter (where p.fetch_status = 'ok' and p.fetched_at is not null),
		'never_read', count(*) filter (where s.orcid is not null and p.scholar is null),
		'pending', count(*) filter (where p.fetch_status = 'pending'),
		'not_found', count(*) filter (where p.fetch_status = 'not_found'),
		'failed', count(*) filter (where p.fetch_status = 'error'),
		-- The number that decides whether to act. Windowed rather than lifetime: a burst
		-- six months ago is history, and a steward needs to know about pressure now.
		'rate_limited', count(*) filter (where p.fetch_rate_limited_at > now() - interval '7 days'),
		'oldest_read', min(p.fetched_at)
	) into _result
	from public.scholars s
	left join public.orcid_profiles p on p.scholar = s.id;

	return _result;
end;
$$;

alter function public.orcid_mirror_health () owner to "postgres";

revoke execute on function public.orcid_mirror_health ()
from
	public,
	anon;

grant
execute on function public.orcid_mirror_health () to authenticated;
