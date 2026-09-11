-- Delivery accounting for outgoing mail (#27): public.send_email's recording of what it did,
-- and public.reconcile_email_delivery's classification of pg_net's answers.
--
-- The problem these exist for: net.http_post is asynchronous. It returns a handle the instant
-- it has queued the request, and the HTTP outcome lands later in net._http_response -- an
-- UNLOGGED table that a restart truncates and that pg_net garbage-collects at pg_net.ttl, six
-- hours by default. send_email() used to discard the handle entirely, so a missing vault
-- secret, a message Resend refused, and a delivered message were indistinguishable
-- afterwards, and a scholar was told "we sent you a link" in all three cases.
--
-- Nothing here touches the network. Responses are synthesized directly into
-- net._http_response, which is how every classification branch can be exercised
-- deterministically -- including the ones (a timeout, a transport error) that are otherwise
-- only reachable by breaking something.

\ir ../_helpers/helpers.sql.inc

begin;

create extension if not exists pgtap
with
	schema extensions;

select
	plan (12);

select
	tests.clear_authentication ();

-- ---- reconcile_email_delivery: one row per classification branch ------------------
-- The trigger is off for these: each row is a stand-in for mail already posted, and firing a
-- real net.http_post would both slow the test and hand us a request id we do not control.
alter table public.emails
disable trigger send_on_email_insert;

-- Six messages, all queued, each about to be given a different answer. request_id values are
-- chosen well above anything pg_net would have issued in a test database so they cannot
-- collide with a real in-flight request.
insert into
	public.emails (id, event, email, subject, message, request_id, delivery, time_sent)
values
	(
		'00000000-0000-4000-8000-0000000000a1',
		'VerifyEmail', 'ok@test.local', 's', 'm', 900000001, 'queued', now()
	),
	(
		'00000000-0000-4000-8000-0000000000a2',
		'VerifyEmail', 'refused@test.local', 's', 'm', 900000002, 'queued', now()
	),
	(
		'00000000-0000-4000-8000-0000000000a3',
		'VerifyEmail', 'unrenderable@test.local', 's', 'm', 900000003, 'queued', now()
	),
	(
		'00000000-0000-4000-8000-0000000000a4',
		'VerifyEmail', 'slow@test.local', 's', 'm', 900000004, 'queued', now()
	),
	(
		'00000000-0000-4000-8000-0000000000a5',
		'VerifyEmail', 'unreachable@test.local', 's', 'm', 900000005, 'queued', now()
	),
	-- No response will ever be written for this one, and it is old enough that there is not
	-- going to be one.
	(
		'00000000-0000-4000-8000-0000000000a6',
		'VerifyEmail', 'lost@test.local', 's', 'm', 900000006, 'queued', now() - interval '20 minutes'
	),
	-- Also unanswered, but too recent to give up on. The distinction is the whole point of
	-- the fifteen-minute floor: a busy worker must not be mistaken for a lost one.
	(
		'00000000-0000-4000-8000-0000000000a7',
		'VerifyEmail', 'recent@test.local', 's', 'm', 900000007, 'queued', now()
	);

insert into
	net._http_response (id, status_code, content, timed_out, error_msg)
values
	(900000001, 200, '{"id":"re_1"}', false, null),
	-- What the `resend` edge function answers when Resend REFUSES the message: a bad API key,
	-- an unverified sender domain, a rejected recipient.
	(900000002, 502, '{"error":"Resend rejected the message"}', false, null),
	-- And what it answers when it could not render or parse the request at all. A different
	-- fault with a different fix, which is why the status survives into delivery_detail.
	(900000003, 400, '{"error":"unknown event"}', false, null),
	(900000004, null, null, true, null),
	(900000005, null, null, false, 'Connection refused');

select
	public.reconcile_email_delivery ();

select
	is (
		(select delivery from public.emails where id = '00000000-0000-4000-8000-0000000000a1'),
		'sent',
		'a 2xx from the resend function counts as sent'
	);

select
	is (
		(select delivery_detail from public.emails where id = '00000000-0000-4000-8000-0000000000a1'),
		null,
		'a delivered message carries no failure detail'
	);

select
	is (
		(select delivery from public.emails where id = '00000000-0000-4000-8000-0000000000a2'),
		'failed',
		'a message Resend refused counts as failed'
	);

-- The status is preserved rather than collapsed into "failed", because 502 (Resend refused
-- it) and 400 (we could not render it) are different faults with different fixes.
select
	alike (
		(select delivery_detail from public.emails where id = '00000000-0000-4000-8000-0000000000a2'),
		'502:%',
		'a refusal keeps the status that distinguishes it from a render fault'
	);

select
	alike (
		(select delivery_detail from public.emails where id = '00000000-0000-4000-8000-0000000000a3'),
		'400:%',
		'a render fault keeps its own status'
	);

select
	is (
		(select delivery from public.emails where id = '00000000-0000-4000-8000-0000000000a4'),
		'failed',
		'a request that timed out counts as failed'
	);

select
	is (
		(select delivery from public.emails where id = '00000000-0000-4000-8000-0000000000a5'),
		'failed',
		'a transport error counts as failed'
	);

-- 'unknown' rather than 'failed': the worker never ran, or it ran and the answer was
-- discarded before this job looked. Neither is knowable from here, and claiming the mail
-- failed would be a guess.
select
	is (
		(select delivery from public.emails where id = '00000000-0000-4000-8000-0000000000a6'),
		'unknown',
		'a request with no answer, old enough to give up on, is unknown rather than failed'
	);

select
	is (
		(select delivery from public.emails where id = '00000000-0000-4000-8000-0000000000a7'),
		'queued',
		'a request with no answer yet is left alone rather than written off'
	);

-- Terminal states are never revisited and the unanswered ones are re-checked, so a second
-- pass over the same data changes nothing. A reconciler that is not idempotent cannot be put
-- on a five-minute schedule.
select
	public.reconcile_email_delivery ();

select
	is (
		(
			select count(*)::int from public.emails
			where id in (
				'00000000-0000-4000-8000-0000000000a1',
				'00000000-0000-4000-8000-0000000000a2',
				'00000000-0000-4000-8000-0000000000a3'
			) and delivery in ('sent', 'failed')
		),
		3,
		'a second pass leaves terminal verdicts untouched'
	);

-- ---- send_email: the failure it can see for itself -------------------------------
-- The other half. This path never reaches pg_net at all, so there is nothing for the
-- reconciler to resolve later: it has to be recorded on the spot, or the row says 'queued'
-- forever about a message that was never posted.
alter table public.emails
enable trigger send_on_email_insert;

delete from vault.secrets
where
	name = 'secret_key';

insert into
	public.emails (id, event, email, subject, message)
values
	(
		'00000000-0000-4000-8000-0000000000b1',
		'VerifyEmail', 'unconfigured@test.local', 's', 'm'
	);

select
	is (
		(select delivery from public.emails where id = '00000000-0000-4000-8000-0000000000b1'),
		'failed',
		'mail that was never posted is recorded as failed, not left queued'
	);

select
	alike (
		(select delivery_detail from public.emails where id = '00000000-0000-4000-8000-0000000000b1'),
		'%secret_key%',
		'and says which piece of configuration was missing'
	);

select
	*
from
	finish ();

rollback;
