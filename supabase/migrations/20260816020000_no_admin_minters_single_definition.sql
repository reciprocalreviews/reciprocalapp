-- Keep the surviving definition of no_admin_minters, comment and all.
--
-- supabase/schemas/currencies.sql declared this function TWICE, with identical
-- executable bodies. The second `create or replace` won, and the second copy was
-- the one without the paragraph explaining why payment-free venues are exempt —
-- so the rationale for the rule was present in the file and absent from the
-- database, which is the copy anyone reads during an incident.
--
-- Removing the duplicate from the schema file is not by itself a no-op, because a
-- comment inside a function body is part of its source: the declarative file would
-- then describe a function the database does not have, and the drift check that
-- keeps schemas/ honest would fail. This migration redefines it to match. No
-- behaviour changes — the predicate and the exception are byte-for-byte what they
-- already were.
create or replace function "public"."no_admin_minters" () RETURNS "trigger" LANGUAGE "plpgsql" SECURITY DEFINER
set
	"search_path" to '' as $$
begin
    -- Payment-free venues never mint or pay, so the anti-self-dealing rule
    -- does not apply; their hidden currency may be minted by an admin.
    if exists (select * from public.venues where public.venues.currency = new.id and (public.venues.admins && new.minters) and not public.venues.payment_free) then
        raise exception 'A venue minter cannot be the admin of the venue currency';
    end if;
    return new;
end;
$$;
