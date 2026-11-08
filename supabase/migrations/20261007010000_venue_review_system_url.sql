-- An optional link to the system where a venue's editors assign reviewers to manuscripts.
-- Assigning someone in RR only records the work for compensation; the pages where
-- approvers assign link here to remind them to assign the person there too.
alter table public.venues
add column review_system_url text default null;

-- http(s) only, and none of the characters that would let the value end a markdown link
-- or an HTML attribute early.
alter table public.venues
add constraint venues_review_system_url_check check (
	review_system_url is null
	or review_system_url ~ '^https?://[^[:space:]()<>"''`\\]+$'
);
