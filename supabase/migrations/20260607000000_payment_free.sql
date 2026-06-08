-- Add a no-payment mode flag to venues and proposals (#123).
-- A payment_free venue still has a (hidden) currency; the flag only gates UI
-- and lets a proposal skip the currency/minter requirement.

alter table public.venues
add column if not exists payment_free boolean not null default false;

alter table public.proposals
add column if not exists payment_free boolean not null default false;

-- A payment-free venue keeps a hidden currency to satisfy the NOT NULL FK, but
-- never mints or pays. The anti-self-dealing rule (a venue admin may not be a
-- minter of its currency) is therefore meaningless for it, and would otherwise
-- block approval whenever the approving steward is also an editor. Exempt
-- payment-free venues from both directions of the check.

create or replace function public.no_minter_admins () returns trigger language plpgsql security definer
set "search_path" to '' as $$
begin
    if new.payment_free then
        return new;
    end if;
    if new.admins && (select minters from public.currencies where id = new.currency) then
        raise exception 'A venue admin cannot be the minter of the venue currency';
    end if;
    return new;
end;
$$;

create or replace function public.no_admin_minters () returns trigger language plpgsql security definer
set "search_path" to '' as $$
begin
    if exists (select * from public.venues where public.venues.currency = new.id and (public.venues.admins && new.minters) and not public.venues.payment_free) then
        raise exception 'A venue minter cannot be the admin of the venue currency';
    end if;
    return new;
end;
$$;
