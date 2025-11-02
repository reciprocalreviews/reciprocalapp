create or replace function public.no_minter_editors() 
returns trigger
as $$
begin
    -- If the editor of this venue is a minter of its currency, raise an exception
    if new.editors && (select minters from public.currencies where id = new.currency) then
        raise exception 'A venue editor cannot be the minter of the venue currency';
    end if;
    return new;
end;
$$ 
language plpgsql
security definer set search_path = '';

create trigger no_minter_editors before 
insert or update on public.venues
for each row execute procedure no_minter_editors();

create or replace function public.no_editor_minters() 
returns trigger 
as $$
begin
    -- If the editor of this venue is a minter of its currency, raise an exception
    if exists (select * from public.venues where public.venues.currency = new.id and (public.venues.editors && new.minters)) then
        raise exception 'A venue minter cannot be the editor of the venue currency';
    end if;
    return new;
end;
$$ language plpgsql
security definer set search_path = '';

create trigger no_editor_minters 
before update on currencies
for each row execute procedure no_editor_minters();