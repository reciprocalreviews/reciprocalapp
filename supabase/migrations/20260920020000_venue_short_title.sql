-- Give a venue a short display name, so the chrome can name it without spending a line on it.
--
-- WHY
--
-- The venue bar added in #176 sits above every route under `/venue/`, and it has to name
-- the venue it belongs to in the space of a tab. "ACM Transactions on Computing Education"
-- does not fit, and "ACM Conference on Innovation and Technology in Computer Science
-- Education" does not come close. Communities already solve this themselves — TOCE, ITiCSE,
-- SIGCSE TS — so the venue says which one it goes by, rather than the interface guessing by
-- truncating a title mid-word.
--
-- WHY NOT ONE OF THE NAMES THE TABLE ALREADY HAS
--
-- `slug` is the closest neighbour and the wrong answer: it is a URL segment, constrained to
-- lowercase, hyphen-separated, at least four characters and globally unique, because those
-- rules are what make an address resolvable and contestable. A display name is none of
-- those things. "SIGCSE TS" has a space and capitals; "CHI" is three characters; two venues
-- in different communities may both go by "TS" without either being wrong. Overloading
-- `slug` would mean either loosening rules that exist for the resolver's sake or refusing
-- names that are simply what a community calls itself.
--
-- `url` is the venue's own website and `title` its full name, so the new column is
-- `short_title`: the same noun as `title`, qualified. "shorthand" is taken by the locale
-- layer, where it means the symbol table every string is interpolated against.
--
-- WHY EMPTY RATHER THAN NULL
--
-- `title`, `description` and `url` are all `text default '' not null` here; only `slug` is
-- nullable, and it is nullable because it carries a unique index where NULL-as-distinct is
-- load-bearing — every venue without an address has to coexist with every other. Nothing
-- like that applies to a display name, so empty string is the unset state and the interface
-- falls back to the full title. Every venue that predates this column is therefore correct
-- the moment it exists, with no backfill.
--------------------------------------
-- 1. The column
--------------------------------------
alter table public.venues
add column if not exists short_title text default ''::text not null;

comment on column public.venues.short_title is 'A short display name shown in the venue bar where the full title does not fit, e.g. "TOCE". Empty until the venue chooses one, in which case the title is shown instead.';

--------------------------------------
-- 2. The bound
--------------------------------------
-- A display cap, not a naming rule. No lower bound, because empty is the unset state; no
-- format rule, because this is prose rather than an address. Twenty characters is generous
-- for an acronym and refuses someone pasting the full title in and getting the bar they
-- were trying to avoid.
alter table public.venues
drop constraint if exists venues_short_title_check;

alter table public.venues
add constraint venues_short_title_check check (length(short_title) <= 20);
