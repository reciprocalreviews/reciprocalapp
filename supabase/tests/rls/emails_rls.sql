-- RLS tests for public.emails.
--
-- Authorization model under test:
--   SELECT  the recipient (scholar = auth.uid()), the sender (sender = auth.uid()),
--           and admins of the email's venue (isAdmin(venue)). Nobody else.
--   INSERT  any authenticated scholar may send an email (with check true); anon
--           has no insert policy and is denied.
--   UPDATE  blocked for everyone (using false → row filtered, no rows affected).
--   DELETE  blocked for everyone (using false → row filtered, no rows affected).
--
-- Inserting a row fires the send_on_email_insert AFTER trigger (net.http_post),
-- so fixtures are inserted in owner context and SELECT/UPDATE/DELETE are probed
-- under switched identities.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
-- Inserting an email fires the send_on_email_insert trigger, which posts to the
-- Resend edge function via net.http_post using the `supabase_url` vault secret
-- (from PUBLIC_SUPABASE_URL). The RLS CI job doesn't set that env, so the URL is
-- null and net.http_post raises. RLS visibility doesn't depend on the email
-- actually being dispatched, so disable the trigger for this rolled-back test.
alter table public.emails disable trigger send_on_email_insert;
select tests.create_scholar('email_recipient@test.local') as recipient \gset
select tests.create_scholar('email_sender@test.local')    as sender    \gset
select tests.create_scholar('email_vadmin@test.local')    as vadmin    \gset
select tests.create_scholar('email_minter@test.local')    as minter    \gset
select tests.create_scholar('email_outsider@test.local')  as outsider  \gset
-- admins and minters must be DISTINCT scholars (no_minter_admins trigger).
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'vadmin']::uuid[]) as ven \gset

-- An email to the recipient, sent by the sender, for the venue.
insert into public.emails (event, scholar, sender, venue, email, subject, message)
values ('test event', :'recipient', :'sender', :'ven',
        'email_recipient@test.local', 'Test Subject', 'Test message')
returning id as eml \gset

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'emails',
	array[
		'senders, recipients, and venue admins can see the emails sent',
		'authenticated scholars can send email',
		'emails can''t be edited',
		'emails can''t be deleted'
	]
);

-- ---- SELECT -------------------------------------------------------------------
select tests.authenticate_as(:'recipient');
select isnt_empty(
	$$ select 1 from public.emails where id = $$ || quote_literal(:'eml'),
	'the recipient can see the email sent to them'
);

select tests.authenticate_as(:'sender');
select isnt_empty(
	$$ select 1 from public.emails where id = $$ || quote_literal(:'eml'),
	'the sender can see the email they sent'
);

select tests.authenticate_as(:'vadmin');
select isnt_empty(
	$$ select 1 from public.emails where id = $$ || quote_literal(:'eml'),
	'a venue admin can see the email sent for their venue'
);

select tests.authenticate_as(:'outsider');
select is_empty(
	$$ select 1 from public.emails where id = $$ || quote_literal(:'eml'),
	'an unrelated scholar cannot see the email'
);

select tests.authenticate_as_anon();
select is_empty(
	$$ select 1 from public.emails where id = $$ || quote_literal(:'eml'),
	'anonymous visitors cannot see emails'
);

-- ---- INSERT -------------------------------------------------------------------
-- Any authenticated scholar may send an email (with check true). The AFTER
-- trigger's net.http_post queues asynchronously and does not fail synchronously.
select tests.authenticate_as(:'outsider');
select lives_ok(
	$$ insert into public.emails (event, sender, email, subject, message)
	   values ('sent event', $$ || quote_literal(:'outsider') || $$,
	           'someone@test.local', 'Hi', 'Body') $$,
	'any authenticated scholar can send an email'
);

-- Anonymous visitors have no insert policy and are denied.
select tests.authenticate_as_anon();
select throws_ok(
	$$ insert into public.emails (event, email, subject, message)
	   values ('anon event', 'anon@test.local', 'Hi', 'Body') $$,
	'42501',
	null,
	'anonymous visitors cannot send emails'
);

-- ---- UPDATE -------------------------------------------------------------------
-- using(false) filters the row: the update touches 0 rows (no error) and the
-- row is unchanged. Even the recipient/sender/admin cannot edit an email.
select tests.authenticate_as(:'vadmin');
update public.emails set subject = 'tampered' where id = :'eml';
select tests.clear_authentication();
select is(
	(select subject from public.emails where id = :'eml'),
	'Test Subject',
	'emails cannot be edited (update is a no-op)'
);

-- ---- DELETE -------------------------------------------------------------------
-- using(false) filters the row: the delete touches 0 rows (no error) and the
-- row is still present.
select tests.authenticate_as(:'vadmin');
delete from public.emails where id = :'eml';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.emails where id = :'eml'),
	1,
	'emails cannot be deleted (delete is a no-op)'
);

select * from finish();
rollback;
