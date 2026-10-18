--------------------------------------
-- Schema
--
-- The reasons a venue offers its approvers when they decline a bid or claim. A decline is
-- addressed to a person, and a free-text explanation written in a hurry can read more
-- harshly than intended; a venue's own neutral wording keeps the answer consistent and
-- makes declines countable. A venue with none requires approvers to write each one.
create table if not exists public.decline_reasons (
	-- The unique id of the reason
	id uuid default gen_random_uuid() not null,
	-- The venue this reason belongs to
	venueid uuid not null,
	-- The words the declined scholar reads
	text text not null,
	-- The presentation order; lower rank is shown first
	rank integer not null,
	-- When the reason was created
	created_at timestamp with time zone default now() not null
);

alter table only public.decline_reasons
add constraint decline_reasons_pkey primary key (id);

alter table only public.decline_reasons
add constraint decline_reasons_venueid_fkey foreign KEY (venueid) references public.venues (id) on delete cascade;

alter table only public.decline_reasons
add constraint decline_reasons_venue_rank_unique unique (venueid, rank);

alter table only public.decline_reasons
add constraint decline_reasons_venue_text_unique unique (venueid, text);

-- The same bound as assignments.decline_reason, which a chosen reason is copied into.
alter table only public.decline_reasons
add constraint decline_reasons_text_check check (char_length(btrim(text)) between 1 and 1000);

alter table only public.decline_reasons
add constraint decline_reasons_rank_check check (rank>=0);

create index decline_reasons_venue_index on public.decline_reasons using btree (venueid);

--------------------------------------
-- Defaults
--
-- Every new venue starts with these, so approvers have neutral wording from the first
-- decline; admins edit them or delete them all to require written reasons.
create or replace function public._seed_decline_reasons () returns trigger language plpgsql security definer
set
	search_path to '' as $$
begin
	insert into public.decline_reasons (venueid, text, rank)
	values
		(new.id, 'We needed someone with different expertise.', 0),
		(new.id, 'We selected a different scholar.', 1),
		(new.id, 'We already have enough reviewers for this submission.', 2),
		(new.id, 'Other qualified scholars were in more need of tokens.', 3),
		(new.id, 'We wanted to avoid a possible conflict of interest.', 4);
	return new;
end;
$$;

alter function public._seed_decline_reasons () OWNER to "postgres";

revoke
execute on function public._seed_decline_reasons ()
from
	public,
	anon,
	authenticated;

create or replace trigger seed_decline_reasons
after insert on public.venues for each row
execute function public._seed_decline_reasons ();

--------------------------------------
-- Security
alter table public.decline_reasons OWNER to postgres;

alter table public.decline_reasons ENABLE row LEVEL SECURITY;

grant all on table public.decline_reasons to anon;

grant all on table public.decline_reasons to authenticated;

grant all on table public.decline_reasons to service_role;

create policy "authenticated scholars can view decline reasons" on public.decline_reasons for
select
	to authenticated using (true);

create policy "only admins can create decline reasons" on public.decline_reasons for INSERT to authenticated
with
	check (public.isAdmin (venueid));

create policy "only admins can update decline reasons" on public.decline_reasons
for update
	to authenticated using (public.isAdmin (venueid));

create policy "only admins can delete decline reasons" on public.decline_reasons for DELETE to authenticated using (public.isAdmin (venueid));

alter publication supabase_realtime
add table decline_reasons;
