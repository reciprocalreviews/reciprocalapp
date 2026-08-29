-- Tests for erasure and export.
--
-- Erasure has to satisfy two things that pull against each other: destroy
-- everything that identifies a person, and leave the records other people depend
-- on intact. The tests below check both directions, because getting either wrong
-- is a failure — one is a broken promise, the other is a corrupted database.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

select tests.clear_authentication();
select tests.create_scholar('era_subject@test.local') as subject \gset
select tests.create_scholar('era_other@test.local') as other \gset
select tests.create_scholar('era_minter@test.local') as minter \gset
select tests.create_scholar('era_admin@test.local') as admin \gset
select tests.create_scholar('era_steward@test.local', true) as steward \gset
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

-- Give the subject some history: tokens, a transaction, and a volunteer record.
select tests.authenticate_as(:'minter');
select public.mint_tokens(:'cur', 4, :'ven', 'erasure fixture') as _m \gset
select tests.clear_authentication();

select tests.authenticate_as(:'admin');
select public.transfer_tokens(:'cur', :'ven', 'venueid', :'subject', 'scholarid', 2, 'payout', null) as _t \gset
select tests.clear_authentication();

select tests.create_role(:'ven', 0) as role \gset
select tests.create_volunteer(:'subject', :'role') as vol \gset

-- Mail about SOMEBODY ELSE that merely copied the subject, and named them as the address a
-- reply should reach. Neither `scholar` nor `sender` is the subject, so neither branch of
-- the scrub matches this row -- which is exactly why the address-keyed pass exists. The
-- send trigger posts to the Resend function via a vault secret the RLS CI job doesn't set,
-- and none of this depends on delivery, so it is disabled for this rolled-back test.
alter table public.emails disable trigger send_on_email_insert;
insert into public.emails (event, scholar, sender, venue, email, cc, reply_to, args)
values ('NewVolunteer', :'other', null, :'ven', 'era_other@test.local',
        array['era_subject@test.local'], 'era_subject@test.local', '[]'::jsonb);

-- ---- Export ---------------------------------------------------------------------
select tests.authenticate_as(:'subject');

select isnt(
	(public.export_scholar_data() -> 'scholar' ->> 'email'),
	null,
	'a scholar can export their own data'
);

select is(
	(select jsonb_array_length(public.export_scholar_data() -> 'transactions')),
	1,
	'the export includes their transactions'
);

-- Only possible because of token_events: before the ledger there was no record of
-- where a scholar's tokens had been.
select cmp_ok(
	(select jsonb_array_length(public.export_scholar_data() -> 'token_history')),
	'>=', 2,
	'the export includes their token history'
);

-- ---- Export authorization -------------------------------------------------------
select throws_ok(
	$$ select public.export_scholar_data( $$ || quote_literal(:'other') || $$ ) $$,
	'RR006',
	null,
	'a scholar cannot export someone else''s data'
);

select tests.authenticate_as(:'steward');
select lives_ok(
	$$ select public.export_scholar_data( $$ || quote_literal(:'subject') || $$ ) $$,
	'a steward can export on a scholar''s behalf'
);

-- ---- Erasure authorization ------------------------------------------------------
select tests.authenticate_as(:'other');
select throws_ok(
	$$ select public.erase_scholar( $$ || quote_literal(:'subject') || $$ ) $$,
	'RR006',
	null,
	'a scholar cannot erase someone else'
);

-- ---- Erasure --------------------------------------------------------------------
select tests.authenticate_as(:'subject');
select lives_ok(
	'select public.erase_scholar()',
	'a scholar can erase themselves'
);
select tests.clear_authentication();

select is(
	(select coalesce(name, '') || coalesce(email, '') || coalesce(orcid, '') || status
		from public.scholars where id = :'subject'),
	'',
	'every identifying field on the scholar is gone'
);

select is(
	(select count(*)::int from auth.users
		where id = :'subject' and (email like 'erased-%@invalid') and encrypted_password is null),
	1,
	'the auth identity is destroyed but the row survives, so the foreign keys hold'
);

-- An erased address must not survive in mail about other people. It did, until `cc` and
-- `reply_to` existed to hold it and nothing looked for it there.
select is(
	(select cc from public.emails
		where event = 'NewVolunteer' and venue = :'ven' and email = 'era_other@test.local'),
	null,
	'the erased scholar is no longer copied on mail about someone else'
);

select is(
	(select reply_to from public.emails
		where event = 'NewVolunteer' and venue = :'ven' and email = 'era_other@test.local'),
	null,
	'the erased scholar is no longer the address replies to that mail would reach'
);

-- Only the erased scholar's address leaves. The rest of the row belongs to other people.
select is(
	(select email from public.emails
		where event = 'NewVolunteer' and venue = :'ven' and email = 'era_other@test.local'),
	'era_other@test.local',
	'the other recipient of that mail keeps their own address'
);

-- ---- What must NOT be destroyed --------------------------------------------------
-- The transaction belongs to the venue's records as much as to the scholar; the
-- tokens are currency. Losing either would corrupt other people's history.
select is(
	(select count(*)::int from public.transactions where to_scholar = :'subject'),
	1,
	'their transactions survive as records of what the venue paid'
);

select is(
	(select count(*)::int from public.tokens where scholar = :'subject'),
	2,
	'their tokens are not destroyed — they are currency, not personal data'
);

-- The property an earlier design would have broken: nulling token_events.scholar
-- would leave every one of those tokens claiming no owner, and the ledger would
-- no longer reconstruct.
select is(
	((public.reconcile_ledger() -> 'invariants' ->> 'replay_mismatches')::int),
	0,
	'the ledger still reconstructs after erasure'
);

-- ---- The record that survives a restore -------------------------------------------
select is(
	(select count(*)::int from public.erasures where subject = :'subject' and completed_at is not null),
	1,
	'the erasure is recorded so it can be re-applied after a restore'
);

-- ---- Erasure destroys the privilege with the identity ----------------------------
-- A tombstone that is still a steward appears on the public /about list as
-- "anonymous", still satisfies isSteward(), and would satisfy set_steward's
-- last-steward guard on behalf of a uuid nobody can sign into — letting the last
-- real steward be demoted while nobody is left who can act.
select tests.authenticate_as(:'steward');
select public.erase_scholar() as _erased_steward \gset

select tests.clear_authentication();
select is(
	(select steward from public.scholars where id = :'steward'),
	false,
	'erasing a steward revokes their stewardship'
);

select * from finish();
rollback;
