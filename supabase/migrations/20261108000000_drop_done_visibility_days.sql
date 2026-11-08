-- The submissions list now shows active and done submissions as separate modes,
-- active by default, so the window that kept recently done submissions in the
-- active list has nothing left to control. Dropping the column drops its check
-- constraint with it.
alter table public.venues drop column done_visibility_days;
