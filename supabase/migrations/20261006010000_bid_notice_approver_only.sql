-- A bid is mailed only to whoever holds the bid-on role's approving role on the
-- submission. The fallbacks to the submission's priority-0 editor and then the venue's
-- admins are gone: they mailed an editor seated on every submission about every bid on
-- one with no associate editor yet. See supabase/schemas/assignments.sql.
create or replace function public.bid_notice_recipients (_submission uuid, _role uuid) returns setof uuid language plpgsql security definer STABLE
set
	search_path to '' as $$
begin
	return query
	select distinct a.scholar
	from public.assignments a
	join public.roles target on target.id = _role
	where a.submission = _submission
	  and a.approved
	  and a.role = target.approver
	  and a.scholar <> (select auth.uid())
	  and not exists (
		select 1
		from public.conflicts x
		where x.submissionid = _submission and x.scholarid = a.scholar
	  )
	  and exists (
		select 1
		from public.assignments b
		where b.submission = _submission
		  and b.role = _role
		  and b.bid
		  and b.scholar = (select auth.uid())
	  );
end;
$$;

alter function public.bid_notice_recipients (uuid, uuid) OWNER to "postgres";

-- Explicitly revoked, not merely un-granted: Supabase's ALTER DEFAULT PRIVILEGES hands anon
-- EXECUTE on every function created in `public` at creation time.
revoke
execute on function public.bid_notice_recipients (uuid, uuid)
from
	public,
	anon;

grant
execute on function public.bid_notice_recipients (uuid, uuid) to authenticated;
