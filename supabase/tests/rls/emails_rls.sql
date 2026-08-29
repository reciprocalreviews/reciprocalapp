-- RLS tests for public.emails.
--
-- Authorization model under test:
--   SELECT  the recipient (scholar = auth.uid()), the sender (sender = auth.uid()),
--           and admins of the email's venue (isAdmin(venue)). Nobody else.
--   INSERT  nobody. There is no insert policy and the privilege is revoked from both
--           authenticated and anon: inserting a row sends branded mail, so allowing it
--           made the pipeline an open relay (any signed-in user, any recipient, any
--           body). Sending goes through public.queue_email and
--           public.request_email_verification instead, which resolve recipients
--           server-side and render the body at send time.
--   UPDATE  blocked for everyone (using false → row filtered, no rows affected).
--   DELETE  blocked for everyone (using false → row filtered, no rows affected).
--
-- Inserting a row fires the send_on_email_insert AFTER trigger (net.http_post),
-- so fixtures are inserted in owner context and SELECT/UPDATE/DELETE are probed
-- under switched identities.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

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

-- The same, but copying the outsider, so the Cc visibility asymmetry below has a row.
insert into public.emails (event, scholar, sender, venue, email, cc, subject, message)
values ('test event', :'recipient', :'sender', :'ven',
        'email_recipient@test.local', array['email_outsider@test.local'],
        'Copied Subject', 'Copied message')
returning id as copied \gset

-- ---- Cc visibility, deliberately asymmetric -----------------------------------
-- `scholar` names only the To recipient, so a Cc'd scholar who is neither the sender nor a
-- venue admin cannot read the row of a message they actually received. That is a decision
-- rather than an oversight: nothing in the application reads this table, venue admins
-- already see these rows through the isAdmin branch, and widening the policy by address
-- would mean resolving the reader's own scholars.email in a correlated subquery on every
-- row read, for no consumer. The one place it genuinely mattered — a scholar's own data
-- export — is handled inside export_scholar_data, which is SECURITY DEFINER and reads
-- past this policy.
select tests.authenticate_as(:'outsider');
select is_empty(
	$$ select 1 from public.emails where id = $$ || quote_literal(:'copied'),
	'a scholar who was merely copied cannot read the email row'
);

select tests.authenticate_as(:'vadmin');
select isnt_empty(
	$$ select 1 from public.emails where id = $$ || quote_literal(:'copied'),
	'a venue admin can still see a message that copied someone'
);

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'emails',
	array[
		'senders, recipients, and venue admins can see the emails sent',
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
-- Nobody may insert directly. This assertion was previously inverted — it asserted that
-- "any authenticated scholar can send an email" was correct behavior, which is exactly the
-- open relay: an insert here names an arbitrary recipient and an arbitrary body, and the
-- AFTER trigger delivers it branded from notifications@reciprocal.reviews.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ insert into public.emails (event, sender, email, subject, message)
	   values ('sent event', $$ || quote_literal(:'outsider') || $$,
	           'someone@test.local', 'Hi', 'Body') $$,
	'42501',
	null,
	'an authenticated scholar cannot insert an email directly'
);

-- The sanctioned path resolves recipients server-side and takes no message body.
select is(
	(select jsonb_array_length(
		public.queue_email('VenueApproved', array['A Venue','venue-id'], array[:'recipient'::uuid], null)
	)),
	1,
	'queue_email queues to a scholar with a verified contact email'
);

-- VerifyEmail renders an argument as a clickable link, so it must not be queueable by a
-- caller — only by request_email_verification, which builds the URL itself.
select throws_ok(
	$$ select public.queue_email('VerifyEmail', array['https://evil.invalid/verify/x'], null, null) $$,
	'P0001',
	null,
	'a caller cannot forge a verification email with a link of their choosing'
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
