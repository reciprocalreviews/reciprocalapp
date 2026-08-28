-- Enforce the admin/minter separation at launch rather than at every moment.
--
-- WHY
--
-- Nobody should administer a venue and mint its currency: that is minting your own money.
-- Two triggers enforced it on every write — `no_minter_admins` on venues, `no_admin_minters`
-- on currencies — which was correct and also made 20260828000000 impossible. The steward
-- approving a proposal is very often one of its editors and so an admin of the venue they
-- just approved; making them the interim minter tripped `no_minter_admins` and rolled the
-- whole approval back. On a platform with one steward that is the ordinary case, not an edge
-- case.
--
-- So the window is narrowed rather than the rule weakened: the overlap is tolerated only
-- while a venue is `inactive` — being configured, invisible, doing no reviewing and moving no
-- tokens. Both triggers key on the venue's own `inactive`, so the check resumes the moment a
-- venue is switched live and stays in force for its whole active life.
--
-- That makes activation itself the gate. `no_minter_admins` fires BEFORE UPDATE on venues; on
-- the update that sets `inactive` to null, the new row is active, so the check runs and
-- refuses. No separate launch trigger is needed, and there is no window where an active venue
-- has an admin who mints.
--
-- The interim overlap is safe on its own terms: `mint_tokens` independently refuses when
-- `isAdmin(_to_venue)`, checked inside the function rather than by trigger, so a steward
-- holding a currency for a venue they administer still cannot mint into it.
--
-- Stewardship is deliberately NOT disqualifying. A steward may mint for a venue they do not
-- administer, permanently — communities have people who hold both roles, and the conflict
-- this guards against is administering and minting, not holding a platform role.
--------------------------------------
create or replace function public.no_minter_admins () returns trigger language plpgsql security definer
set
	"search_path" to '' as $$
begin
    if new.payment_free then
        return new;
    end if;
    -- Being configured: the overlap is allowed here and nowhere else. Switching the venue
    -- live runs this same check against the new row, which is what makes activation the gate.
    if new.inactive is not null then
        return new;
    end if;
    if new.admins && (select minters from public.currencies where id = new.currency) then
        raise exception 'A venue admin cannot be the minter of the venue currency' using errcode = 'RR015';
    end if;
    return new;
end;
$$;

alter function public.no_minter_admins () OWNER to "postgres";

grant all on FUNCTION public.no_minter_admins () to "anon";

grant all on FUNCTION public.no_minter_admins () to "authenticated";

grant all on FUNCTION public.no_minter_admins () to "service_role";

--------------------------------------
-- The mirror: a currency may not gain a minter who administers a venue using it. Same
-- narrowing, from the currency's side — an inactive venue's admins are ignored.
create or replace function public.no_admin_minters () returns trigger language plpgsql security definer
set
	"search_path" to '' as $$
begin
    -- Payment-free venues never mint or pay, so the anti-self-dealing rule
    -- does not apply; their hidden currency may be minted by an admin.
    if exists (
        select *
        from public.venues
        where public.venues.currency = new.id
            and (public.venues.admins && new.minters)
            and not public.venues.payment_free
            and public.venues.inactive is null
    ) then
        raise exception 'A venue minter cannot be the admin of the venue currency' using errcode = 'RR015';
    end if;
    return new;
end;
$$;

alter function public.no_admin_minters () OWNER to "postgres";

grant all on FUNCTION public.no_admin_minters () to "anon";

grant all on FUNCTION public.no_admin_minters () to "authenticated";

grant all on FUNCTION public.no_admin_minters () to "service_role";
