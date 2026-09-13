-- Tests for the notification preference machinery: public.notification_allowed, the
-- constraint on public.notification_settings.event, and public.queue_email's use of both.
--
-- What is under test:
--   DEFAULT    absence of a row means the registry's default, which is NOT always "on" any
--              more -- a preference may ship off and wait to be asked for.
--   SILENCING  queue_email skips a silenced scholar, and reports having skipped them, since
--              the recipient list it returns surfaces to users as a feedback banner.
--   DEFERRAL   silencing a preference also silences the templates that defer to it via
--              `silencedBy`, which is what lets a reminder share the control of the notice
--              it chases instead of needing a second checkbox.
--   BOUNDARY   a scholar cannot silence consequential mail. The event column was deliberately
--              unconstrained while nothing read it; queue_email reads it now, and the write
--              policies carry no column boundary, so without the foreign key any scholar
--              could switch off the notice that they had been billed.
--
-- Inserting an email fires the send_on_email_insert AFTER trigger (net.http_post via the
-- `supabase_url` vault secret). The RLS CI job doesn't set that env, so the URL is null and
-- the post raises. Nothing here depends on mail actually being dispatched, so the trigger is
-- disabled for this rolled-back test, exactly as emails_rls.sql and new_volunteer_notice.sql do.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan (18);

alter table public.emails disable trigger send_on_email_insert;

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('np_plain@test.local')  as plain  \gset
select tests.create_scholar('np_muted@test.local')  as muted  \gset
select tests.create_scholar('np_noaddr@test.local') as noaddr \gset
update public.scholars set email = null where id = :'noaddr';

-- The sender. queue_email refuses an unauthenticated caller.
select tests.create_scholar('np_sender@test.local') as sender \gset

insert into public.notification_settings (scholar, event, enabled)
values (:'muted', 'SubmissionsNeedEditors', false);

-- ---- notification_allowed ------------------------------------------------------

select is (
	public.notification_allowed(:'plain', 'SubmissionsNeedEditors'), true,
	'1. no row means the registry default, which for this preference is on'
);

select is (
	public.notification_allowed(:'muted', 'SubmissionsNeedEditors'), false,
	'2. a row saying false silences the notice'
);

-- The deferral. SubmissionNeedsEditor (singular) carries `silencedBy` pointing at the plural,
-- so one control governs both; a scholar who muted the news does not get the singular form.
select is (
	public.notification_allowed(:'muted', 'SubmissionNeedsEditor'), false,
	'3. silencing a preference also silences the templates that defer to it'
);

select is (
	public.notification_allowed(:'plain', 'SubmissionNeedsEditor'), true,
	'4. and leaves them alone for a scholar who did not'
);

-- Consequential mail has no row in optional_emails, so it matches nothing and always sends.
-- This is the fail-safe direction: a template accidentally missing from the seed keeps being
-- delivered rather than going quiet.
select is (
	public.notification_allowed(:'muted', 'SubmissionCharged'), true,
	'5. a template with no preference is consequential and always allowed'
);

select is (
	public.notification_allowed(:'muted', 'NotATemplateAtAll'), true,
	'6. an unknown event is likewise allowed rather than swallowed'
);

-- ---- Defaults ------------------------------------------------------------------
-- A preference may ship OFF. "Absence means on" was fine for one notice and would have opted
-- every existing scholar into two dozen at once.
update public.notification_preferences set default_on = false where key = 'SubmissionsNeedEditors';

select is (
	public.notification_allowed(:'plain', 'SubmissionsNeedEditors'), false,
	'7. a default-off preference sends nothing to a scholar who never expressed an opinion'
);

insert into public.notification_settings (scholar, event, enabled)
values (:'plain', 'SubmissionsNeedEditors', true);

select is (
	public.notification_allowed(:'plain', 'SubmissionsNeedEditors'), true,
	'8. and an explicit opt-in turns it on'
);

delete from public.notification_settings where scholar = :'plain';
update public.notification_preferences set default_on = true where key = 'SubmissionsNeedEditors';

-- ---- The write boundary ---------------------------------------------------------

select throws_ok (
	format($$ insert into public.notification_settings (scholar, event, enabled)
	          values (%L::uuid, 'SubmissionCharged', false) $$, :'plain'),
	'23503',
	null,
	'9. a scholar cannot silence consequential mail'
);

select throws_ok (
	format($$ insert into public.notification_settings (scholar, event, enabled)
	          values (%L::uuid, 'SubmissionNeedsEditor', false) $$, :'plain'),
	'23503',
	null,
	'10. nor name a deferring template rather than the preference governing it'
);

-- ---- queue_email ------------------------------------------------------------------

select tests.authenticate_as(:'sender');

select lives_ok (
	format($$ select public.queue_email('SubmissionsNeedEditors', array['1','V','v'], array[%L::uuid, %L::uuid, %L::uuid]) $$,
	       :'plain', :'muted', :'noaddr'),
	'11. queue_email accepts a mixed batch of recipients'
);

select is (
	(select count(*)::int from public.emails
	 where event = 'SubmissionsNeedEditors' and scholar = :'plain'), 1,
	'12. the scholar who did not silence it is mailed'
);

select is (
	(select count(*)::int from public.emails
	 where event = 'SubmissionsNeedEditors' and scholar = :'muted'), 0,
	'13. the scholar who silenced it is not'
);

-- The returned recipient list drives a feedback banner, so it has to agree with what was
-- actually queued. The predicate is repeated in queue_email's second query for this reason.
select is (
	(select jsonb_array_length(
		public.queue_email('SubmissionsNeedEditors', array['1','V','v'],
		                   array[:'plain'::uuid, :'muted'::uuid, :'noaddr'::uuid]))),
	1,
	'14. and queue_email reports only the recipients it really wrote to'
);

select tests.clear_authentication();

-- ---- queue_reminder_email ----------------------------------------------------------
-- The scheduled reminders' way in. It takes no caller, because the cron is not a person; it
-- keeps queue_email's real safety property, which is that it accepts no address and no body.

select is (
	public.queue_reminder_email('SubmissionsReady', array['3', 'A Venue', 'a-venue'], :'plain'),
	1,
	'15. a reminder is queued for a scholar who has not silenced it'
);

-- The editor-waiting reminder REUSES the SubmissionsNeedEditors template rather than having
-- one of its own, so the preference `muted` set above governs the reminder too. This is the
-- whole reason `silencedBy` exists: chasing a thing is the same subscription as being told
-- about it, and two checkboxes for it would be a worse settings page.
select is (
	public.queue_reminder_email('SubmissionsNeedEditors', array['2', 'A Venue', 'a-venue'], :'muted'),
	0,
	'16. and not for one who silenced the notice it chases'
);

select is (
	public.queue_reminder_email('SubmissionsReady', array['1', 'A Venue', 'a-venue'], :'noaddr'),
	0,
	'17. nor for a scholar with no verified contact address'
);

-- CompensationPending defers to CompensationRequested the same way.
select is (
	(select preference from public.optional_emails where event = 'CompensationPending'),
	'CompensationRequested',
	'18. the compensation reminder is governed by the compensation preference'
);

select * from finish ();
rollback;
