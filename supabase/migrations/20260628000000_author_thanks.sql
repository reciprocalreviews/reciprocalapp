-- Author thank-you notes to reviewers (#22). Text-only, per-submission,
-- vetted by default, delivered server-side to preserve reviewer anonymity.
-- Mirrors supabase/schemas/thanks.sql and the venues.vet_thanks column.

--------------------------------------
-- Venue setting: vet thank-you notes before sharing them (default on).
alter table public.venues
add column if not exists vet_thanks boolean default true not null;

--------------------------------------
-- thanks table
create type public.thanks_status as enum('proposed', 'approved', 'declined');

alter type public.thanks_status OWNER to "postgres";

create table if not exists public.thanks (
	id uuid default gen_random_uuid() not null,
	submission uuid not null,
	venue uuid not null,
	author uuid not null,
	message text not null,
	status public.thanks_status not null default 'proposed',
	approver uuid,
	decline_reason text,
	created_at timestamp with time zone default now() not null,
	constraint thanks_submission_author_key unique (submission, author),
	constraint thanks_message_check check (char_length(btrim(message)) > 0 and char_length(message) <= 1000)
);

alter table public.thanks OWNER to "postgres";

alter table only public.thanks
add constraint thanks_pkey primary key (id);

alter table only public.thanks
add constraint thanks_submission_fkey foreign KEY (submission) references public.submissions (id) on delete cascade;

alter table only public.thanks
add constraint thanks_venue_fkey foreign KEY (venue) references public.venues (id) on delete cascade;

alter table only public.thanks
add constraint thanks_author_fkey foreign KEY (author) references public.scholars (id) on delete cascade;

alter table only public.thanks
add constraint thanks_approver_fkey foreign KEY (approver) references public.scholars (id);

create index thanks_submission_index on public.thanks using btree (submission);

create index thanks_venue_index on public.thanks using btree (venue);

--------------------------------------
-- Security
alter table public.thanks ENABLE row LEVEL SECURITY;

grant all on table public.thanks to "anon";

grant all on table public.thanks to "authenticated";

grant all on table public.thanks to "service_role";

revoke
update on public.thanks
from
	authenticated;

grant
update (message) on public.thanks to authenticated;

create policy "authors, vetters, and recipients can see thanks" on public.thanks for
select
	to authenticated using (
		(
			(author=(select auth.uid () as uid))
			or public.isAdmin (venue)
			or public.isPriorityZero (venue)
			or (
				status='approved'::public.thanks_status
				and public.isAssigned (submission)
			)
		)
	);

create policy "authors can propose thanks on done submissions" on public.thanks for INSERT to authenticated
with
	check (
		(
			author=(select auth.uid () as uid)
			and public.isAuthor (submission)
			and status='proposed'::public.thanks_status
			and exists (
				select 1 from public.submissions s
				where s.id=submission and s.status='done'::public.submission_status
			)
		)
	);

create policy "authors can edit pending thanks" on public.thanks
for update
	to authenticated using (
		(author=(select auth.uid () as uid) and status='proposed'::public.thanks_status)
	)
with
	check (
		(author=(select auth.uid () as uid) and status='proposed'::public.thanks_status)
	);

create policy "authors can withdraw pending thanks" on public.thanks for DELETE to authenticated using (
	(author=(select auth.uid () as uid) and status='proposed'::public.thanks_status)
);

alter publication supabase_realtime
add table thanks;

--------------------------------------
-- Functions
--
-- queue_thanks_emails: resolve the right recipients for a note and queue
-- already-rendered emails to them. The bodies are rendered from the localizable
-- template registry (src/email/templates.ts) in the application layer and passed
-- in; this function only fans them out — to recipients the caller may not be
-- permitted to see — by inserting rows into public.emails, which the resend
-- function then brands and delivers. sender is left null so a recipient cannot
-- read the author's id off the email row. Authorization is per audience, and is
-- what stops an author from bypassing vetting to message reviewers directly:
--   'recipients' -> the submission's approved assignees (excluding the author);
--                   allowed only for an approved note, by a venue admin / editor,
--                   or by the author themselves when the venue vetting is off.
--   'vetters'    -> venue admins + priority-0 editors; the author notifies them.
--   'author'     -> the note's author; a venue admin / editor notifies them.
create or replace function public.queue_thanks_emails (
	_thanks_id uuid,
	_audience text,
	_subject text,
	_message text
) returns integer language plpgsql security definer
set
	search_path = public, pg_temp as $function$
declare
	_caller uuid;
	_t public.thanks;
	_vet boolean;
	_count integer;
begin
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	select * into _t from public.thanks where id = _thanks_id;
	if not found then
		raise exception 'Thank-you note not found';
	end if;
	select vet_thanks into _vet from public.venues where id = _t.venue;

	if _audience = 'recipients' then
		if _t.status <> 'approved' then
			raise exception 'Only an approved note can be delivered';
		end if;
		if not (
			public.isAdmin(_t.venue)
			or public.isPriorityZero(_t.venue)
			or (not _vet and _caller = _t.author)
		) then
			raise exception 'You are not authorized to deliver this note';
		end if;
		insert into public.emails (event, scholar, sender, venue, email, subject, message)
		select 'ThanksReceived', s.id, null, _t.venue, s.email, _subject, _message
		from (
			select distinct a.scholar
			from public.assignments a
			where a.submission = _t.submission and a.approved = true and a.scholar <> _t.author
		) r
		join public.scholars s on s.id = r.scholar
		where s.email is not null;

	elsif _audience = 'vetters' then
		if _caller <> _t.author then
			raise exception 'You are not authorized to notify vetters';
		end if;
		insert into public.emails (event, scholar, sender, venue, email, subject, message)
		select 'ThanksPendingReview', s.id, null, _t.venue, s.email, _subject, _message
		from (
			select unnest(admins) as scholar from public.venues where id = _t.venue
			union
			select v.scholarid
			from public.volunteers v
			join public.roles r on r.id = v.roleid
			where r.venueid = _t.venue and r.priority = 0 and v.accepted = 'accepted'
		) vt
		join public.scholars s on s.id = vt.scholar
		where s.email is not null and s.id <> _caller;

	elsif _audience = 'author' then
		if not (public.isAdmin(_t.venue) or public.isPriorityZero(_t.venue)) then
			raise exception 'You are not authorized to notify the author';
		end if;
		insert into public.emails (event, scholar, sender, venue, email, subject, message)
		select 'ThanksDeclined', s.id, null, _t.venue, s.email, _subject, _message
		from public.scholars s
		where s.id = _t.author and s.email is not null;

	else
		raise exception 'Unknown thanks email audience';
	end if;

	get diagnostics _count = row_count;
	return _count;
end;
$function$;

revoke execute on function public.queue_thanks_emails (uuid, text, text, text) from public;
grant execute on function public.queue_thanks_emails (uuid, text, text, text) to authenticated;

--------------------------------------
-- RPCs (defined in migration 20260628000000_author_thanks.sql)
--
-- propose_thanks: an author submits a thank-you note for a done submission.
-- Inserts the note (proposed, or approved when the venue has vetting off), or
-- revises a previously declined note. Returns the id, resolved status, and venue
-- so the app layer can render and queue the right notification.
create or replace function public.propose_thanks (
	_submission uuid,
	_message text
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
declare
	_caller uuid;
	_venue uuid;
	_status public.submission_status;
	_vet boolean;
	_id uuid;
	_new_status public.thanks_status;
	_existing_id uuid;
	_existing_status public.thanks_status;
begin
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- The submission must exist, be done, and have the caller as an author.
	select venue, status into _venue, _status from public.submissions where id = _submission;
	if _venue is null then
		raise exception 'Submission not found';
	end if;
	if _status <> 'done' then
		raise exception 'You can only thank reviewers after the submission is done';
	end if;
	if not public.isAuthor(_submission) then
		raise exception 'Only an author of the submission can thank its reviewers';
	end if;

	-- Note content must be non-empty and bounded (mirrors the table constraint).
	if _message is null or char_length(btrim(_message)) = 0 then
		raise exception 'A thank-you note cannot be empty';
	end if;
	if char_length(_message) > 1000 then
		raise exception 'A thank-you note must be at most 1000 characters';
	end if;

	-- Does this venue vet notes before sharing them?
	select vet_thanks into _vet from public.venues where id = _venue;

	-- One note per author per submission. A pending or already-shared note can't
	-- be replaced; a previously declined note may be revised and resubmitted.
	select id, status into _existing_id, _existing_status
	from public.thanks where submission = _submission and author = _caller;

	if _existing_id is not null then
		if _existing_status <> 'declined' then
			raise exception 'You have already sent thanks for this submission';
		end if;
		update public.thanks
			set message = _message,
				status = case when _vet then 'proposed'::public.thanks_status else 'approved'::public.thanks_status end,
				approver = null,
				decline_reason = null,
				created_at = now()
			where id = _existing_id
			returning id, status into _id, _new_status;
	else
		insert into public.thanks (submission, venue, author, message, status)
		values (
			_submission, _venue, _caller, _message,
			case when _vet then 'proposed'::public.thanks_status else 'approved'::public.thanks_status end
		)
		returning id, status into _id, _new_status;
	end if;

	return jsonb_build_object(
		'thanks_id', _id, 'status', _new_status, 'venue', _venue, 'submission', _submission
	);
end;
$function$;

revoke execute on function public.propose_thanks (uuid, text) from public;
grant execute on function public.propose_thanks (uuid, text) to authenticated;

-- approve_thanks: a venue admin or priority-0 editor approves a proposed note.
-- Returns the venue, submission, and note text so the app layer can render and
-- queue the delivery to reviewers.
create or replace function public.approve_thanks (
	_id uuid
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
declare
	_caller uuid;
	_t public.thanks;
begin
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	select * into _t from public.thanks where id = _id;
	if not found then
		raise exception 'Thank-you note not found';
	end if;
	if _t.status <> 'proposed' then
		raise exception 'This note has already been reviewed';
	end if;
	if not (public.isAdmin(_t.venue) or public.isPriorityZero(_t.venue)) then
		raise exception 'Only a venue admin or editor can review thank-you notes';
	end if;

	update public.thanks set status = 'approved', approver = _caller where id = _id;

	return jsonb_build_object('venue', _t.venue, 'submission', _t.submission, 'message', _t.message);
end;
$function$;

revoke execute on function public.approve_thanks (uuid) from public;
grant execute on function public.approve_thanks (uuid) to authenticated;

-- decline_thanks: a venue admin or priority-0 editor declines a proposed note,
-- recording a reason. Returns the venue and submission so the app layer can
-- render and queue the notification to the author. The note is never delivered.
create or replace function public.decline_thanks (
	_id uuid,
	_reason text
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
declare
	_caller uuid;
	_t public.thanks;
begin
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	select * into _t from public.thanks where id = _id;
	if not found then
		raise exception 'Thank-you note not found';
	end if;
	if _t.status <> 'proposed' then
		raise exception 'This note has already been reviewed';
	end if;
	if not (public.isAdmin(_t.venue) or public.isPriorityZero(_t.venue)) then
		raise exception 'Only a venue admin or editor can review thank-you notes';
	end if;

	update public.thanks set status = 'declined', approver = _caller, decline_reason = _reason where id = _id;

	return jsonb_build_object('venue', _t.venue, 'submission', _t.submission);
end;
$function$;

revoke execute on function public.decline_thanks (uuid, text) from public;
grant execute on function public.decline_thanks (uuid, text) to authenticated;
