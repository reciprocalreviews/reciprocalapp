-- #109 resolved: token balances are private.
--
-- The question was whether a scholar's balance is public, private, or visible
-- only to editors. It is now decided: NOT public, and no feature is wanted to
-- make it public. The audience is the holder, the people holding roles involved
-- in bidding at a venue using that currency, and that currency's minters.
--
-- Until now `public.tokens` carried `for select to authenticated using (true)`,
-- so any signed-in scholar could read who held how much of what across every
-- venue on the platform -- by listing the table directly, whatever the UI showed.
--
-- WHERE THE RULE LIVES, AND WHY IT IS SPLIT IN TWO
--
-- A policy is evaluated once PER ROW, and this table has one row per token, so a
-- reserve holding a community's supply pays for the policy a quarter of a million
-- times. The audience rule ("is the caller part of this currency's reviewing?")
-- needs three EXISTS clauses, and putting that in the policy would undo the
-- indexing work of 20260830000000 outright.
--
-- So the policy keeps only what a per-row test must answer -- is this row mine,
-- or is it a venue's -- and every cross-scholar read goes through
-- public.scholar_balances, which is SECURITY DEFINER and asks
-- public.can_see_balances ONCE per call. That is the same division of labour the
-- rest of this schema already uses, and it is what lets the audience be this
-- broad at no per-row cost.

--------------------------------------
-- 1. The policy.
drop policy if exists "tokens are visible to authenticated scholars" on public.tokens;

-- Balances are private (#109). This policy used to be `using (true)`, so every
-- signed-in scholar could read who held how much of what across every venue on
-- the platform -- by listing this table directly, whatever the UI chose to show.
--
-- Two branches, and deliberately no more. Both are plain column comparisons, so
-- this stays exactly as cheap as `using (true)` was and the composite indexes
-- above still serve it: a policy is evaluated once PER ROW, and a token table
-- has a row per token, so anything cleverer here is paid for a quarter of a
-- million times per venue.
--
-- Cross-scholar reads are not served by this policy at all. They go through
-- public.scholar_balances, which is SECURITY DEFINER and asks
-- public.can_see_balances ONCE per call rather than once per row -- the same
-- division of labour every other RPC in this schema uses, and the reason the
-- audience rule can be as broad as it is without costing anything.
create policy "tokens are visible to their holder, and venue reserves to any scholar" on public.tokens for
select
	to authenticated using (
		-- Your own balance. Null-safe by construction: a venue-held row has
		-- `scholar is null`, and `null = uuid` is null, not true.
		scholar=(
			select
				auth.uid ()
		)
		-- A venue's reserve, which is institutional rather than personal. A scholar
		-- deciding whether to volunteer somewhere is entitled to know whether the
		-- venue can actually pay, and #109 is about what individuals hold.
		or venue is not null
	);

--------------------------------------
-- 2. The audience predicate.
create or replace function public.can_see_balances (_currency uuid) returns boolean language sql stable security definer
set
	search_path='' as $function$
	select
		-- Minters answer for the currency's supply.
		public.isminter((select auth.uid()), _currency)
		-- Venue admins, who need not be volunteers anywhere.
		or exists (
			select 1 from public.venues ve
			where ve.currency = _currency
				and (select auth.uid()) = any (ve.admins)
		)
		-- The reviewing pool: anyone holding an accepted, still-active role at a
		-- venue using this currency. `active` matters -- unvolunteering keeps the
		-- row (it is what stops a welcome grant being made twice), so accepting
		-- alone would leave visibility behind forever.
		or exists (
			select 1
			from public.volunteers v
			join public.roles r on r.id = v.roleid
			join public.venues ve on ve.id = r.venueid
			where v.scholarid = (select auth.uid())
				and v.accepted = 'accepted'
				and v.active
				and ve.currency = _currency
		);
$function$;

alter function public.can_see_balances (uuid) OWNER to "postgres";

revoke
execute on function public.can_see_balances (uuid)
from
	public,
	anon;

grant
execute on function public.can_see_balances (uuid) to authenticated;

--------------------------------------
-- 3. scholar_balances, which bypasses RLS and so must carry the rule itself.
-- Before this it had no checks at all: an arbitrary scholar-id array in, exact
-- balances out. scholars.id is publicly readable, so every id was harvestable and
-- this was the platform's entire balance table, open to anyone with the key.
create or replace function public.scholar_balances (_currency uuid, _scholars uuid[]) returns table (scholar uuid, count bigint) language sql stable security definer
set
	search_path='' as $function$
	select t.scholar, count(*)
	from public.tokens t
	where t.currency = _currency
		and t.scholar = any (_scholars)
		and (
			-- Your own balance is always yours to see.
			t.scholar = (select auth.uid())
			-- Everyone else's, only for the currency's reviewing audience. Constant
			-- for the call, so it is evaluated once and not once per token.
			or public.can_see_balances(_currency)
		)
	group by t.scholar;
$function$;

--------------------------------------
-- 4. The affordability check the new-submission form actually needs -- a boolean
-- per author, never an amount. See the function's own comment.
create or replace function public.authors_can_cover (
	_currency uuid,
	_scholars uuid[],
	_amounts integer[]
) returns table (scholar uuid, covered boolean) language sql stable security definer
set
	search_path='' as $function$
	select
		a.scholar,
		(
			select count(*) from public.tokens t
			where t.currency = _currency and t.scholar = a.scholar
		) >= a.amount
	from unnest(_scholars, _amounts) as a (scholar, amount);
$function$;

alter function public.authors_can_cover (uuid, uuid[], integer[]) OWNER to "postgres";

revoke
execute on function public.authors_can_cover (uuid, uuid[], integer[])
from
	public,
	anon;

grant
execute on function public.authors_can_cover (uuid, uuid[], integer[]) to authenticated;
