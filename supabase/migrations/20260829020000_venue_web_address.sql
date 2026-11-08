-- Give a venue a web address, so its URLs stop being UUIDs.
--
-- WHY
--
-- Every venue route is keyed by `venues.id`, so a reviewer following a link from an email
-- arrives at `/venue/8f3c…/submission/2b91…` — two opaque identifiers in one address. The
-- same UUID goes into the snippets an editor pastes into HotCRP, into the venue's own
-- breadcrumbs, and into every notification. Nobody can read one, say one aloud, or tell
-- two venues apart by looking.
--
-- So a venue may choose a short, globally unique name — `acm-chi` — and be reached by it.
-- The id keeps working: `getVenueByPath` resolves either form and the layout redirects the
-- id form to the address, so mail already sent and bookmarks already saved still land.
--
-- The address is `slug` here rather than `address`, which in this schema means an email
-- address, and rather than `url`, which the table already uses for the venue's own website.
--
-- WHY THE FORMAT IS NARROW
--
-- Four characters minimum: three-letter acronyms are the ones most likely to be contested
-- ("CHI", "SIG"), and handing the first arrival a name that a dozen communities have equal
-- claim to is not a race worth running. Lowercase only, so an address is the same address
-- however it is typed. And never a UUID's shape, because the resolver decides which column
-- to query by looking at the segment: a slug that could pass for an id would make that
-- choice ambiguous, and `[a-z][a-z0-9-]*` alone admits `abcdef12-3456-7890-abcd-ef1234567890`.
--------------------------------------
-- 1. The column
--------------------------------------
alter table public.venues
add column if not exists slug text;

comment on column public.venues.slug is 'The venue''s web address: the path segment it is reached by, in place of its id. Null until the venue chooses one. Released the moment it is changed — nothing reserves a former address, so links to it break.';

alter table public.venues
drop constraint if exists venues_slug_check;

alter table public.venues add constraint venues_slug_check check (
	slug is null
	or (
		slug ~ '^[a-z][a-z0-9]*(-[a-z0-9]+)*$'
		and length(slug) between 4 and 40
		and slug !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
	)
);

-- Globally unique, and null is not a value: a btree unique index treats nulls as distinct,
-- so every venue that has not chosen an address coexists with every other.
create unique index if not exists venues_slug_key on public.venues (slug);

--------------------------------------
-- 2. An address is required to go live
--------------------------------------
-- Only the TRANSITION is guarded, not the state. A blanket "active implies an address"
-- constraint would be true of the data we want but false of the data we have: every venue
-- already live has no address, and such a rule would refuse every subsequent edit to it —
-- title, compensation, roles — until someone renamed it. Guarding the transition asks for
-- an address at the one moment an admin is already deciding to publish, and leaves a
-- running venue alone.
create or replace function public.venue_needs_address_to_activate () RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
set
	"search_path" to '' as $$
begin
	if new.inactive is null and old.inactive is not null and new.slug is null then
		raise exception 'A venue needs a web address before it can be activated' using errcode = 'RR016';
	end if;
	return new;
end;
$$;

alter function public.venue_needs_address_to_activate () OWNER to postgres;

drop trigger if exists venue_needs_address_to_activate on public.venues;

create trigger venue_needs_address_to_activate before
update on public.venues for each row
execute function public.venue_needs_address_to_activate ();

--------------------------------------
-- 3. The one email producer that lives in the database
--------------------------------------
-- Everything else that links to a venue in mail does so from the application layer, which
-- now resolves the address before queueing. This function queues its own message, so it
-- resolves its own link: `coalesce(v.slug, v.id::text)`, the same rule, so a venue that has
-- not named itself still gets a working link.
create or replace function public._notify_new_volunteer (_venueid uuid, _roleid uuid, _scholarid uuid) returns integer language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_top_role uuid;
	_top_role_name text;
	_ids uuid[];
	_addrs text[];
	_reply_to text;
	_name text;
	_venue_title text;
	_venue_path text;
	_role_name text;
begin
	-- The venue's top-priority role -- whatever this venue calls it. The name is data, so it
	-- is read here and handed to the template rather than assumed to be "Editor".
	-- `order by r.id limit 1` mirrors create_submission: priority is unique per venue by
	-- construction (create_role assigns max+1, and 20260828030000 renumbered the existing
	-- ones densely), and this stays deterministic if it ever isn't. Resolving a single role
	-- id also means a scholar who somehow holds two priority-0 roles is addressed once.
	select r.id, r.name into _top_role, _top_role_name
	from public.roles r
	where r.venueid = _venueid and r.priority = 0
	order by r.id
	limit 1;

	if _top_role is null then
		return 0;
	end if;

	-- The new volunteer. scholars.email holds only VERIFIED addresses, so null here means
	-- there is no reply path. The notice still goes out: the news is what matters, and a
	-- scholar with no contact address is precisely the one an editor needs the profile link
	-- for. The null is also what makes the branded footer fall back to naming the stewards
	-- instead of promising that a reply reaches a person.
	select coalesce(nullif(btrim(s.name), ''), 'A scholar'), s.email
	into _name, _reply_to
	from public.scholars s
	where s.id = _scholarid;

	-- The venue's title for the prose and its path for the link. The path is the venue's web
	-- address once it has chosen one, and its id until then; both resolve, so a venue that
	-- has not named itself still gets a working link.
	select v.title, coalesce(v.slug, v.id::text)
	into _venue_title, _venue_path
	from public.venues v
	where v.id = _venueid;
	select r.name into _role_name from public.roles r where r.id = _roleid;

	-- Who hears about it: ACTIVE, ACCEPTED holders of that role, with a verified contact
	-- address, who have not silenced this notice, and never the new volunteer themselves --
	-- someone can hold the top role here and still volunteer for another open one, and
	-- telling them their own news is noise.
	--
	-- Note this filters `active`, which public.isPriorityZero() does not. The app's own
	-- convention is the one followed here (see emailEditorsOf in SupabaseCRUD, which filters
	-- active and accepted): someone who has stopped volunteering should not be mailed about
	-- the venue's newcomers. Left as a comment rather than "fixed" in isPriorityZero,
	-- because that function answers a question about authority and this one answers a
	-- question about mail, and they are not obliged to agree.
	--
	-- Ordered by how long they have held the role, id breaking ties, so the To slot is
	-- deterministic and the venue's longest-standing holder is the one addressed. The
	-- tiebreak is load-bearing rather than decorative: supabase/seed.sql gives many
	-- volunteer rows an identical created_at to the microsecond, so ordering by it alone is
	-- genuinely ambiguous.
	select array_agg(s.id order by v.created_at, s.id),
	       array_agg(s.email order by v.created_at, s.id)
	into _ids, _addrs
	from public.volunteers v
	join public.scholars s on s.id = v.scholarid
	where v.roleid = _top_role
		and v.active
		and v.accepted = 'accepted'
		and s.id <> _scholarid
		and s.email is not null
		and not exists (
			select 1
			from public.notification_settings n
			where n.scholar = s.id and n.event = 'NewVolunteer' and not n.enabled
		);

	-- Nobody reachable. Saying nothing is right: the volunteering succeeded, and a venue
	-- whose top-role holders have no verified address is a venue configuration problem
	-- rather than a failure of volunteering. Note this is the DEFAULT state of a freshly
	-- approved venue, whose admins have not necessarily verified an address yet.
	if _addrs is null or cardinality(_addrs) = 0 then
		return 0;
	end if;

	-- Resend caps a message at 50 addresses across to + cc + bcc and rejects the whole send
	-- past that -- a rejection pg_net swallows, so the notice would vanish rather than fail
	-- loudly. No real venue has 50 people in its top role; this slice is what keeps that
	-- true rather than merely likely.
	if cardinality(_addrs) > 50 then
		_ids := _ids[1:50];
		_addrs := _addrs[1:50];
	end if;

	-- ONE row, one send, one thread: the first holder in To, the rest in Cc. Reply reaches
	-- the volunteer; Reply All reaches the volunteer and every other holder. A row per
	-- recipient would mean each of them receiving one copy addressed to them plus N-1 as a
	-- Cc, and the replies never converging.
	insert into public.emails (
		event, scholar, sender, venue, email, cc, reply_to, subject, message, args
	) values (
		'NewVolunteer',
		_ids[1],
		-- Attribution, as queue_email records its caller. This makes the row readable by the
		-- volunteer through the SELECT policy's `sender` branch, which leaks nothing:
		-- scholars.email is already readable by anyone signed in. thanks.sql nulls its
		-- sender because reviewer anonymity depends on it; nothing here is anonymous -- the
		-- volunteer is named in the body.
		_scholarid,
		_venueid,
		_addrs[1],
		-- nullif so a lone holder yields NULL rather than the empty array the check
		-- constraint in part 1 forbids.
		nullif(_addrs[2:], '{}'::text[]),
		_reply_to,
		-- Null so the body is rendered at send time from the template registry, which is the
		-- invariant that keeps prose out of the API.
		null,
		null,
		-- EVERY element must be non-null. jsonb_build_array with a NULL yields JSON null;
		-- the edge function validates args as z.array(z.string()), so one null makes the
		-- WHOLE body fail to parse, the function answers 400, and pg_net swallows it -- the
		-- email simply never arrives, with nothing on screen to say so. scholars.name is
		-- nullable (a fresh ORCID account has none) and role and venue titles default to '',
		-- so every one of them is coalesced.
		jsonb_build_array(
			_name,
			coalesce(nullif(btrim(_role_name), ''), 'volunteer'),
			coalesce(nullif(btrim(_venue_title), ''), 'a venue'),
			_scholarid::text,
			_venue_path,
			coalesce(nullif(btrim(_top_role_name), ''), 'top')
		)
	);

	return cardinality(_addrs);
end;
$function$;
