-- Close the dormant DELETE and UPDATE paths on public.volunteers.
--
-- WHY: a volunteer row is what stops a venue's welcome grant being made twice.
-- `create_volunteer` and `accept_role_invite` decide the grant by counting the
-- scholar's existing volunteer rows at the role's venue, and `volunteers.active`
-- exists precisely so that unvolunteering keeps the record — its column comment
-- has said so since the table was written. Two client paths let a scholar erase
-- that record anyway, and both were reachable only by a hand-crafted PostgREST
-- request with a user JWT:
--
--   1. DELETE. "admins and volunteers can delete" admitted venue admins and the
--      volunteering scholar. No UI calls it, CRUD declares no deleteVolunteer,
--      and no RPC deletes a volunteer row; the only admin action that removes
--      them is deleting the whole role, which cascades and is unaffected by RLS
--      on the child table. Delete your row, re-volunteer, be welcomed again.
--
--   2. UPDATE. "volunteers can update" authorized the row and said nothing
--      about columns, over the table-wide UPDATE that `grant all` confers. Its
--      USING expression constrains `scholarid` only, so a scholar could repoint
--      their own row's `roleid` to a role at another venue — dropping their
--      count at the original venue to zero and earning its welcome grant a
--      second time. Reassigning the row to a different `scholarid` was already
--      refused: Postgres applies a policy's USING expression as its WITH CHECK
--      when none is given, and that expression names `scholarid`. `roleid`
--      simply never appeared in it.
--
-- Following the tokens/transactions pattern: the table privilege is revoked
-- (a column-level revoke is a no-op while `grant all` stands) AND the intent is
-- recorded in the policies so the pgTAP suite can assert it. The RPCs are
-- SECURITY DEFINER and owned by postgres, so none of this touches them.
-- service_role is untouched, so administrative surgery still has a path.
--
-- INSERT is deliberately left alone: it has a live, legitimate direct path (an
-- admin adds anyone; a scholar self-volunteers for a non-invite-only role), and
-- inserting directly only forfeits the inserter's own welcome grant.

--------------------------------------
-- 1. UPDATE: narrowed to the columns a volunteer may write. The WITH CHECK is
-- spelled out rather than left to default from USING; it is the same expression
-- and so changes nothing today, but it means a later widening of USING (to admit
-- venue admins, say) cannot silently widen what a row may become as well.
revoke
update on public.volunteers
from
	authenticated,
	anon;

grant
update (active, expertise, papers) on public.volunteers to authenticated;

drop policy "volunteers can update" on public.volunteers;

create policy "volunteers can update" on public.volunteers
for update
	to authenticated using (
		(
			(
				select
					auth.uid () as uid
			)=scholarid
		)
	)
with
	check (
		(
			(
				select
					auth.uid () as uid
			)=scholarid
		)
	);

--------------------------------------
-- 2. DELETE: denied outright.
drop policy "admins and volunteers can delete" on public.volunteers;

create policy "volunteers cannot be deleted" on public.volunteers for DELETE to authenticated using (false);

revoke delete on public.volunteers
from
	authenticated,
	anon;
