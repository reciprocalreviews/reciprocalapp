-- !!! DO NOT EVER ACCIDENTALLY RUN THIS FILE IN YOUR PRODUCTION DATABASE !!!
-- This only meant for local testing.
-- Create local users
insert into
	auth.users (
		instance_id,
		id,
		aud,
		role,
		email,
		encrypted_password,
		email_confirmed_at,
		invited_at,
		confirmation_token,
		confirmation_sent_at,
		recovery_token,
		recovery_sent_at,
		email_change_token_new,
		email_change,
		email_change_sent_at,
		last_sign_in_at,
		raw_app_meta_data,
		raw_user_meta_data,
		is_super_admin,
		created_at,
		updated_at,
		phone,
		phone_confirmed_at,
		phone_change,
		phone_change_token,
		phone_change_sent_at,
		email_change_token_current,
		email_change_confirm_status,
		banned_until,
		reauthentication_token,
		reauthentication_sent_at,
		is_sso_user,
		deleted_at,
		is_anonymous
	)
values
	(
		'00000000-0000-0000-0000-000000000000',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
		'authenticated',
		'authenticated',
		'r1@uni.edu',
		'$2a$10$Z1.OMhB4ppiHyIshPx7sz.3rfv1kywhjFWpHWso3DYlUB1D1TJjj.',
		'2025-10-19 22:00:38.377967+00',
		null,
		'',
		null,
		'',
		'2025-10-19 22:08:42.414842+00',
		'',
		'',
		null,
		'2025-10-19 22:08:47.45125+00',
		'{"provider": "email", "providers": ["email"]}',
		'{"sub": "7ff8621a-cbe0-4789-bbee-f008d38c4ac7", "email": "r1@uni.edu", "email_verified": true, "phone_verified": false}',
		null,
		'2025-10-19 22:00:38.374+00',
		'2025-10-19 22:08:47.453525+00',
		null,
		null,
		'',
		'',
		null,
		'',
		'0',
		null,
		'',
		null,
		'false',
		null,
		'false'
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac8',
		'authenticated',
		'authenticated',
		'r2@uni.edu',
		'$2a$10$Z1.OMhB4ppiHyIshPx7sz.3rfv1kywhjFWpHWso3DYlUB1D1TJjj.',
		'2025-10-19 22:00:38.377967+00',
		null,
		'',
		null,
		'',
		'2025-10-19 22:08:42.414842+00',
		'',
		'',
		null,
		'2025-10-19 22:08:47.45125+00',
		'{"provider": "email", "providers": ["email"]}',
		'{"sub": "7ff8621a-cbe0-4789-bbee-f008d38c4ac8", "email": "r2@uni.edu", "email_verified": true, "phone_verified": false}',
		null,
		'2025-10-19 22:00:38.374+00',
		'2025-10-19 22:08:47.453525+00',
		null,
		null,
		'',
		'',
		null,
		'',
		'0',
		null,
		'',
		null,
		'false',
		null,
		'false'
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac9',
		'authenticated',
		'authenticated',
		'r3@uni.edu',
		'$2a$10$Z1.OMhB4ppiHyIshPx7sz.3rfv1kywhjFWpHWso3DYlUB1D1TJjj.',
		'2025-10-19 22:00:38.377967+00',
		null,
		'',
		null,
		'',
		'2025-10-19 22:08:42.414842+00',
		'',
		'',
		null,
		'2025-10-19 22:08:47.45125+00',
		'{"provider": "email", "providers": ["email"]}',
		'{"sub": "7ff8621a-cbe0-4789-bbee-f008d38c4ac9", "email": "r3@uni.edu", "email_verified": true, "phone_verified": false}',
		null,
		'2025-10-19 22:00:38.374+00',
		'2025-10-19 22:08:47.453525+00',
		null,
		null,
		'',
		'',
		null,
		'',
		'0',
		null,
		'',
		null,
		'false',
		null,
		'false'
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'7ff8621a-cbe0-4789-bbee-f008d38c4aca',
		'authenticated',
		'authenticated',
		'r4@uni.edu',
		'$2a$10$Z1.OMhB4ppiHyIshPx7sz.3rfv1kywhjFWpHWso3DYlUB1D1TJjj.',
		'2025-10-19 22:00:38.377967+00',
		null,
		'',
		null,
		'',
		'2025-10-19 22:08:42.414842+00',
		'',
		'',
		null,
		'2025-10-19 22:08:47.45125+00',
		'{"provider": "email", "providers": ["email"]}',
		'{"sub": "7ff8621a-cbe0-4789-bbee-f008d38c4aca", "email": "r4@uni.edu", "email_verified": true, "phone_verified": false}',
		null,
		'2025-10-19 22:00:38.374+00',
		'2025-10-19 22:08:47.453525+00',
		null,
		null,
		'',
		'',
		null,
		'',
		'0',
		null,
		'',
		null,
		'false',
		null,
		'false'
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		'authenticated',
		'authenticated',
		'r5@uni.edu',
		'$2a$10$Z1.OMhB4ppiHyIshPx7sz.3rfv1kywhjFWpHWso3DYlUB1D1TJjj.',
		'2025-10-19 22:00:38.377967+00',
		null,
		'',
		null,
		'',
		'2025-10-19 22:08:42.414842+00',
		'',
		'',
		null,
		'2025-10-19 22:08:47.45125+00',
		'{"provider": "email", "providers": ["email"]}',
		'{"sub": "7ff8621a-cbe0-4789-bbee-f008d38c4acb", "email": "r5@uni.edu", "email_verified": true, "phone_verified": false}',
		null,
		'2025-10-19 22:00:38.374+00',
		'2025-10-19 22:08:47.453525+00',
		null,
		null,
		'',
		'',
		null,
		'',
		'0',
		null,
		'',
		null,
		'false',
		null,
		'false'
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		'authenticated',
		'authenticated',
		'author1@uni.edu',
		'$2a$10$4lVmpmDpZuRTwwtl82JmKOuMIsIUNbf6ygJYO9m7V808kSlOb0r5W',
		'2025-10-19 22:01:42.35992+00',
		null,
		'',
		null,
		'',
		'2025-10-19 22:15:01.192536+00',
		'',
		'',
		null,
		'2025-10-19 22:15:07.828069+00',
		'{"provider": "email", "providers": ["email"]}',
		'{"sub": "b8a805bf-0aae-4443-9185-de019a8715cb", "email": "author1@uni.edu", "email_verified": true, "phone_verified": false}',
		null,
		'2025-10-19 22:01:42.357405+00',
		'2025-10-19 22:15:07.830042+00',
		null,
		null,
		'',
		'',
		null,
		'',
		'0',
		null,
		'',
		null,
		'false',
		null,
		'false'
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		'authenticated',
		'authenticated',
		'ae@uni.edu',
		'$2a$10$4lVmpmDpZuRTwwtl82JmKOuMIsIUNbf6ygJYO9m7V808kSlOb0r5W',
		'2025-10-19 22:01:42.35992+00',
		null,
		'',
		null,
		'',
		'2025-10-19 22:15:01.192536+00',
		'',
		'',
		null,
		'2025-10-19 22:15:07.828069+00',
		'{"provider": "email", "providers": ["email"]}',
		'{"sub": "b8a805bf-0aae-4443-9185-de019a8715db", "email": "ae@uni.edu", "email_verified": true, "phone_verified": false}',
		null,
		'2025-10-19 22:01:42.357405+00',
		'2025-10-19 22:15:07.830042+00',
		null,
		null,
		'',
		'',
		null,
		'',
		'0',
		null,
		'',
		null,
		'false',
		null,
		'false'
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'authenticated',
		'authenticated',
		'editor@uni.edu',
		'$2a$10$yjCwuy5aByQoh20o5THmjulaAXi0DIEbdGDr0Wn3vuSrX7XgxgjyO',
		'2025-10-19 21:59:30.452557+00',
		null,
		'',
		null,
		'',
		'2025-10-19 22:13:00.134955+00',
		'',
		'',
		null,
		'2025-10-19 22:13:08.982757+00',
		'{"provider": "email", "providers": ["email"]}',
		'{"sub": "d181d165-8b6a-4d79-ad28-a9aece21d813", "email": "editor@uni.edu", "email_verified": true, "phone_verified": false}',
		null,
		'2025-10-19 21:59:30.445372+00',
		'2025-10-19 22:13:08.986024+00',
		null,
		null,
		'',
		'',
		null,
		'',
		'0',
		null,
		'',
		null,
		'false',
		null,
		'false'
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'b8a805bf-0aae-4443-9185-de019a8715ec',
		'authenticated',
		'authenticated',
		'author2@uni.edu',
		'$2a$10$4lVmpmDpZuRTwwtl82JmKOuMIsIUNbf6ygJYO9m7V808kSlOb0r5W',
		'2025-10-19 22:01:42.35992+00',
		null,
		'',
		null,
		'',
		'2025-10-19 22:15:01.192536+00',
		'',
		'',
		null,
		'2025-10-19 22:15:07.828069+00',
		'{"provider": "email", "providers": ["email"]}',
		'{"sub": "b8a805bf-0aae-4443-9185-de019a8715ec", "email": "author2@uni.edu", "email_verified": true, "phone_verified": false}',
		null,
		'2025-10-19 22:01:42.357405+00',
		'2025-10-19 22:15:07.830042+00',
		null,
		null,
		'',
		'',
		null,
		'',
		'0',
		null,
		'',
		null,
		'false',
		null,
		'false'
	);

insert into
	auth.identities (
		provider_id,
		user_id,
		identity_data,
		provider,
		last_sign_in_at,
		created_at,
		updated_at,
		id
	)
values
	(
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
		'{"sub": "7ff8621a-cbe0-4789-bbee-f008d38c4ac7", "email": "r1@uni.edu", "email_verified": false, "phone_verified": false}',
		'email',
		'2025-10-19 22:00:38.375679+00',
		'2025-10-19 22:00:38.375695+00',
		'2025-10-19 22:00:38.375695+00',
		'24f92ade-b454-4757-945e-cc7e3805390d'
	),
	(
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		'{"sub": "b8a805bf-0aae-4443-9185-de019a8715cb", "email": "author1@uni.edu", "email_verified": false, "phone_verified": false}',
		'email',
		'2025-10-19 22:01:42.358867+00',
		'2025-10-19 22:01:42.358883+00',
		'2025-10-19 22:01:42.358883+00',
		'c221be80-1e04-4664-b8d3-0ef407ee6a85'
	),
	(
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'{"sub": "d181d165-8b6a-4d79-ad28-a9aece21d813", "email": "editor@uni.edu", "email_verified": false, "phone_verified": false}',
		'email',
		'2025-10-19 21:59:30.449912+00',
		'2025-10-19 21:59:30.449967+00',
		'2025-10-19 21:59:30.449967+00',
		'd03732ca-fa0b-409c-ac8f-5c0aaa035b14'
	),
	(
		'b8a805bf-0aae-4443-9185-de019a8715ec',
		'b8a805bf-0aae-4443-9185-de019a8715ec',
		'{"sub": "b8a805bf-0aae-4443-9185-de019a8715ec", "email": "author2@uni.edu", "email_verified": false, "phone_verified": false}',
		'email',
		'2025-10-19 22:01:42.358867+00',
		'2025-10-19 22:01:42.358883+00',
		'2025-10-19 22:01:42.358883+00',
		'e55976f2-2f15-4886-c0e5-2f1629ff8d37'
	),
	(
		'7ff8621a-cbe0-4789-bbee-f008d38c4aca',
		'7ff8621a-cbe0-4789-bbee-f008d38c4aca',
		'{"sub": "7ff8621a-cbe0-4789-bbee-f008d38c4aca", "email": "r4@uni.edu", "email_verified": false, "phone_verified": false}',
		'email',
		'2025-10-19 22:00:38.375679+00',
		'2025-10-19 22:00:38.375695+00',
		'2025-10-19 22:00:38.375695+00',
		'24f92ade-b454-4757-945e-cc7e3805390e'
	),
	(
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		'{"sub": "7ff8621a-cbe0-4789-bbee-f008d38c4acb", "email": "r5@uni.edu", "email_verified": false, "phone_verified": false}',
		'email',
		'2025-10-19 22:00:38.375679+00',
		'2025-10-19 22:00:38.375695+00',
		'2025-10-19 22:00:38.375695+00',
		'24f92ade-b454-4757-945e-cc7e3805390f'
	);

-- Local dev/CI sign-in uses an email+password grant (see src/routes/login.ts and the
-- dev form in the login page): ORCID custom OIDC can't be configured in local Supabase,
-- so every seeded user gets the same known password to sign in with. NEVER in production
-- (this whole file is local-only — see the warning at the top).
update auth.users
set
	encrypted_password=extensions.crypt ('password', extensions.gen_salt ('bf'));

insert into
	public.currencies (id, name, description, minters)
values
	(
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'Epistemology',
		'One token is one referee report''s worth of labor: the reading, the checking, and the writing that a single careful review takes. Authors spend them to have work reviewed; referees earn them by reviewing. Only the minters this community trusts to count can make more.',
		'{"7ff8621a-cbe0-4789-bbee-f008d38c4ac7"}'
	);

update public.scholars
set
	orcid='0000-0001-2345-6789',
	"name"='Rigor Russ',
	"email"='r1@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Two or three reviews a term, no more. I would rather write one report I can defend than four I cannot.'
where
	id='7ff8621a-cbe0-4789-bbee-f008d38c4ac7';

update public.scholars
set
	orcid='0000-0001-2345-6790',
	"name"='Reese Urcher',
	"email"='r2@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='On sabbatical and reading widely this year, so send me things a little outside my area — I actually have the time to be careful with them.'
where
	id='7ff8621a-cbe0-4789-bbee-f008d38c4ac8';

update public.scholars
set
	orcid='0000-0001-2345-6791',
	"name"='Sai Entist',
	"email"='r3@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Available, and glad to take the methods-heavy submissions nobody else bids on. Fair warning: I will ask to see your data.'
where
	id='7ff8621a-cbe0-4789-bbee-f008d38c4ac9';

update public.scholars
set
	orcid='0000-0001-2345-6792',
	"name"='Foot Note',
	"email"='author1@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Mostly submitting rather than reviewing at the moment, but I will always take one if an editor is stuck.'
where
	id='b8a805bf-0aae-4443-9185-de019a8715cb';

update public.scholars
set
	orcid='0000-0001-2345-6793',
	"name"='Scholar Lee',
	"email"='editor@uni.edu',
	"available"='true',
	"steward"='true',
	"status"='Editor-in-chief. If a submission has been sitting longer than it should, or a decision does not make sense to you, write to me directly — that is what the role is for.'
where
	id='d181d165-8b6a-4d79-ad28-a9aece21d813';

update public.scholars
set
	orcid='0000-0001-2345-6794',
	"name"='Grant Seeker',
	"email"='ae@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Associate editor for methods and measurement. Slow in grant season, quick the rest of the year.'
where
	id='b8a805bf-0aae-4443-9185-de019a8715db';

update public.scholars
set
	orcid='0000-0001-2345-6795',
	"name"='Ann Thesis',
	"email"='author2@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Finishing a dissertation, so I am keeping reviews close to my own work: knowledge claims drawn from small-n studies.'
where
	id='b8a805bf-0aae-4443-9185-de019a8715ec';

update public.scholars
set
	orcid='0000-0001-2345-6796',
	"name"='Manny Script',
	"email"='r4@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Available. New to this venue and would like a few submissions to calibrate against more experienced referees.'
where
	id='7ff8621a-cbe0-4789-bbee-f008d38c4aca';

update public.scholars
set
	orcid='0000-0001-2345-6797',
	"name"='Anne Notation',
	"email"='r5@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Available, though teaching means I need three weeks rather than two. Say so in the invitation if that is too slow and I will decline cleanly rather than be late.'
where
	id='7ff8621a-cbe0-4789-bbee-f008d38c4acb';

-- The venue below is the only one the seed creates, and its description reads like
-- a real aims-and-scope rather than a disclaimer. That is deliberate: it is what
-- makes the venue pages worth looking at when judging the interface. The fact that
-- none of this is real is carried by the cast of characters, and by the banner at
-- the top of this file -- NOT by the copy, which has to stand in for a real venue's.
insert into
	public.venues (
		"id",
		"title",
		"description",
		"url",
		"currency",
		"welcome_amount",
		"admins",
		"inactive",
		"slug"
	)
values
	(
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'Transactions on Knowledge',
		'Transactions on Knowledge publishes empirical and theoretical work on how knowledge is made, certified, and circulated — including work on peer review itself. We take submissions from any discipline, on one condition: state the claim plainly enough that somebody can argue with it. Every submission goes to three referees, and every referee is paid for the labor.',
		'https://tok.science.org',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'20',
		'{"d181d165-8b6a-4d79-ad28-a9aece21d813"}',
		null,
		'knowledge'
	);

insert into
	public.proposals (
		"id",
		"title",
		"url",
		"editors",
		"census",
		"venue"
	)
values
	(
		'82246928-ad37-11f0-a071-bb5db9b6e698',
		'Transactions on Knowledge',
		'https://toce.acm.edu',
		'{"editor@uni.edu"}',
		'500',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6'
	);

insert into
	public.roles (
		"id",
		"venueid",
		"name",
		"description",
		"invited",
		"biddable",
		"approver",
		"priority",
		"desired_assignments"
	)
values
	(
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac99',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'Editor',
		'Desk rejects, assigns an Associate Editor, and makes final decisions.',
		'true',
		'false',
		null,
		0,
		1
	),
	(
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'Associate Editor',
		'Invites reviewers and makes recommendations.',
		'true',
		'false',
		null,
		1,
		1
	),
	(
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'Reviewer',
		'Evaluates a submission.',
		'false',
		'true',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		2,
		3
	);

insert into
	public.submission_types (
		id,
		venue,
		name,
		description,
		revision_of,
		submission_cost
	)
values
	(
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'Research Article',
		'An original research contribution that this venue has not seen before. Handled by an editor, an associate editor, and three referees.',
		null,
		10
	),
	(
		'2b7f9c3a-1d4e-4f6a-8b2c-3e5a7d9f1c00',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'Research Article - Revision',
		'A revision of an article this venue has already reviewed. It costs less because the referees are usually the same ones, and reading a revision is less work than reading it cold.',
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		4
	);

insert into
	public.compensation (submission_type, role, amount, rationale)
values
	(
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac99',
		1,
		'Submissions typically take much less time to manage than to meta-review.'
	),
	(
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		10,
		'Associate editors get 10 tokens for handling a submission, as they are often as much work as writing a review.'
	),
	(
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		10,
		'Reviewers get 10 tokens for handling a submission.'
	);

insert into
	public.tokens (id, currency, scholar, venue)
values
	(
		'ec74bbba-ad38-11f0-97f0-dbd5772afa08',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74bbba-ad38-11f0-97f0-dbd5772afa09',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74db86-ad38-11f0-97f1-8bcd8f9c8254',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74db86-ad38-11f0-97f1-8bcd8f9c8255',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74dc3a-ad38-11f0-97f2-f39915e62804',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74dc3a-ad38-11f0-97f2-f39915e62806',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74dc6c-ad38-11f0-97f3-6fe2b890b86c',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74dc6c-ad38-11f0-97f3-6fe2b890b86d',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74dc9e-ad38-11f0-97f4-07fb88341648',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74dc9e-ad38-11f0-97f4-07fb88341649',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74dcd0-ad38-11f0-97f5-73d10c3cf0e2',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74dcd0-ad38-11f0-97f5-73d10c3cf0e3',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74dcf8-ad38-11f0-97f6-033df7b8246c',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74dcf8-ad38-11f0-97f6-033df7b8246d',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74dd20-ad38-11f0-97f7-1776b16e0855',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74dd20-ad38-11f0-97f7-1776b16e0856',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74de7e-ad38-11f0-97f8-6392d6dffa33',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74de7e-ad38-11f0-97f8-6392d6dffa34',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74df00-ad38-11f0-97f9-f310de92543e',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74df00-ad38-11f0-97f9-f310de92543f',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74df32-ad38-11f0-97fa-13316bd5a967',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74df32-ad38-11f0-97fa-13316bd5a968',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74df82-ad38-11f0-97fb-1744e83622a7',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74df82-ad38-11f0-97fb-1744e83622a8',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74dfb4-ad38-11f0-97fc-979f820dc15f',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74dfb4-ad38-11f0-97fc-979f820dc160',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74dfdc-ad38-11f0-97fd-fb653a615af7',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74dfdc-ad38-11f0-97fd-fb653a615af8',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74e004-ad38-11f0-97fe-57efeb37df3a',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74e004-ad38-11f0-97fe-57efeb37df3b',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74e036-ad38-11f0-97ff-9b4690da85ed',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74e05e-ad38-11f0-9800-6fcd74da877e',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74e086-ad38-11f0-9801-7f99e92ce9a0',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74e0b8-ad38-11f0-9802-3f3bd3aa0e75',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'ec74e0e0-ad38-11f0-9803-cf3d40db77f3',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null
	),
	(
		'fa74e000-ad38-11f0-a200-000000000001',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715ec',
		null
	),
	(
		'fa74e000-ad38-11f0-a200-000000000002',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715ec',
		null
	),
	(
		'fa74e000-ad38-11f0-a200-000000000003',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715ec',
		null
	),
	(
		'fa74e000-ad38-11f0-a200-000000000004',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715ec',
		null
	),
	(
		'fa74e000-ad38-11f0-a200-000000000005',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715ec',
		null
	),
	(
		'fa74e000-ad38-11f0-a200-000000000006',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715ec',
		null
	),
	(
		'fa74e000-ad38-11f0-a200-000000000007',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715ec',
		null
	),
	(
		'fa74e000-ad38-11f0-a200-000000000008',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715ec',
		null
	),
	(
		'fa74e000-ad38-11f0-a200-000000000009',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715ec',
		null
	),
	(
		'fa74e000-ad38-11f0-a200-00000000000a',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715ec',
		null
	);

-- Seed the venue's token reserve so role approvers have something to pay
-- out when they click Complete on an assignment. Sized for usability
-- testing (50 tokens = 5 reviewer compensations at 10 tokens each).
insert into
	public.tokens (currency, scholar, venue)
select
	'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
	null,
	'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6'
from
	generate_series(1, 50);

-- Give author1 generous headroom so the submission end-to-end tests (which
-- spend a submission cost plus a resubmission cost, and may re-run on CI) have
-- plenty to pay with across a suite run.
insert into
	public.tokens (currency, scholar, venue)
select
	'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
	'b8a805bf-0aae-4443-9185-de019a8715cb',
	null
from
	generate_series(1, 100);

insert into
	public.volunteers (
		"id",
		"scholarid",
		"roleid",
		"created_at",
		"expertise",
		"active",
		"accepted"
	)
values
	(
		'f9bfb99c-ad37-11f0-83e8-875a9c988799',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac99',
		'2025-10-19 22:07:17.336976+00',
		'peer review, research ethics, editorial process',
		'true',
		'accepted'
	),
	(
		'f9bfb99c-ad37-11f0-83e8-875a9c9887b5',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2025-10-19 22:07:17.336976+00',
		'peer review, replication, research methods',
		'true',
		'accepted'
	),
	(
		'f9bfb99c-ad37-11f0-83e8-875a9c9887b6',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac8',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2025-10-19 22:07:17.336976+00',
		'peer review, history of science, testimony',
		'true',
		'accepted'
	),
	(
		'f9bfb99c-ad37-11f0-83e8-875a9c9887b7',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac9',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2025-10-19 22:07:17.336976+00',
		'peer review, research methods, measurement',
		'true',
		'accepted'
	),
	(
		'fefccf8a-ad37-11f0-a9a3-7bcd0d5d1666',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		'2025-10-19 22:07:26.125662+00',
		'peer review, editorial process, measurement',
		'true',
		'accepted'
	),
	(
		'f9bfb99c-ad37-11f0-83e8-875a9c9887b8',
		'7ff8621a-cbe0-4789-bbee-f008d38c4aca',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2025-10-19 22:07:17.336976+00',
		'peer review, knowledge representation, citation analysis',
		'true',
		'accepted'
	),
	(
		'f9bfb99c-ad37-11f0-83e8-875a9c9887b9',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2025-10-19 22:07:17.336976+00',
		'annotation, knowledge representation, peer review',
		'true',
		'accepted'
	),
	(
		'f9bfb99c-ad37-11f0-83e8-875a9c9887ba',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac99',
		'2025-10-19 22:07:17.336976+00',
		'',
		'false',
		'invited'
	),
	(
		'f9bfb99c-ad37-11f0-83e8-875a9c9887bb',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		'2025-10-19 22:07:17.336976+00',
		'',
		'false',
		'invited'
	);

insert into
	public.transactions (
		"id",
		"created_at",
		"creator",
		"from_scholar",
		"from_venue",
		"to_scholar",
		"to_venue",
		"tokens",
		"currency",
		"purpose",
		"status"
	)
values
	(
		'06125654-ad39-11f0-9804-177447a4d1ee',
		'2025-10-19 22:14:47.508161+00',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null,
		'{"ec74bbba-ad38-11f0-97f0-dbd5772afa08","ec74db86-ad38-11f0-97f1-8bcd8f9c8254","ec74dc3a-ad38-11f0-97f2-f39915e62804","ec74dc6c-ad38-11f0-97f3-6fe2b890b86c","ec74dc9e-ad38-11f0-97f4-07fb88341648","ec74dcd0-ad38-11f0-97f5-73d10c3cf0e2","ec74dcf8-ad38-11f0-97f6-033df7b8246c","ec74dd20-ad38-11f0-97f7-1776b16e0855","ec74de7e-ad38-11f0-97f8-6392d6dffa33","ec74df00-ad38-11f0-97f9-f310de92543e","ec74df32-ad38-11f0-97fa-13316bd5a967","ec74df82-ad38-11f0-97fb-1744e83622a7","ec74dfb4-ad38-11f0-97fc-979f820dc15f","ec74dfdc-ad38-11f0-97fd-fb653a615af7","ec74e004-ad38-11f0-97fe-57efeb37df3a"}',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'Payment for submission',
		'approved'
	),
	(
		'0d920b9a-1c9f-4cb2-80cd-20266002f9f3',
		'2026-03-01 23:07:58.77327+00',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'{"ec74e036-ad38-11f0-97ff-9b4690da85ed"}',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'Welcome grant for joining the editorial board',
		'approved'
	),
	(
		'30ace877-5c9f-42e1-abf0-225c093ffc8b',
		'2026-03-01 23:08:20.021985+00',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'{"ec74e0b8-ad38-11f0-9802-3f3bd3aa0e75"}',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'Compensation for handling TOK-2025-002',
		'approved'
	),
	(
		'32709a67-e5f1-4df4-a9a6-4199cf6204ec',
		'2026-03-01 23:08:26.356946+00',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'{"ec74e0e0-ad38-11f0-9803-cf3d40db77f3"}',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'Compensation for handling TOK-2025-003',
		'approved'
	),
	(
		'9ced2fce-d3e7-4f12-a352-ba9d896c45bd',
		'2026-03-01 23:08:11.789909+00',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'{"ec74e05e-ad38-11f0-9800-6fcd74da877e"}',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'Thanks for stepping in as emergency referee over the winter break',
		'approved'
	),
	(
		'bc8686f1-5a2e-4c84-a1cf-61b837eef381',
		'2026-03-01 23:08:14.954625+00',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'{"ec74e086-ad38-11f0-9801-7f99e92ce9a0"}',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'Honorarium for compiling the annual editorial report',
		'approved'
	),
	-- Pre-staged for manually testing the decline-transaction flow (#114).
	-- r1 (creator) requested compensation; visit as editor@uni.edu, go to
	-- /venue/c60d7d0a-…/transactions, click Decline on this row, enter a
	-- reason, confirm twice. Mailpit should then show a "Your transaction
	-- was declined" email to r1@uni.edu naming editor@uni.edu as decliner.
	(
		'00000000-0000-0000-0000-000000000114',
		'2026-03-01 23:08:30.000000+00',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
		null,
		'{"00000000-0000-0000-0000-000000000000"}',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'Compensation for reviewing TOK-2025-001',
		'proposed'
	);

;

insert into
	public.submissions (
		id,
		venue,
		externalid,
		previousid,
		submission_type,
		authors,
		payments,
		transactions,
		title,
		expertise,
		status
	)
values
	(
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c12',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'TOK-2025-001',
		null,
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		array['b8a805bf-0aae-4443-9185-de019a8715cb']::uuid[],
		array[15]::integer[],
		array['06125654-ad39-11f0-9804-177447a4d1ee']::uuid[],
		'A Study on the Effectiveness of Peer Review Incentives in Academic Publishing',
		'peer review, incentives, field study',
		'reviewing'
	),
	(
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c13',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'TOK-2025-002',
		null,
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		array['7ff8621a-cbe0-4789-bbee-f008d38c4ac7']::uuid[],
		array[15]::integer[],
		array['06125654-ad39-11f0-9804-177447a4d1ee']::uuid[],
		'A Windmill Study on the Failures of Peer Review',
		'mechanism design, peer review',
		'reviewing'
	),
	(
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c14',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'TOK-2025-003',
		null,
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		array['7ff8621a-cbe0-4789-bbee-f008d38c4ac7']::uuid[],
		array[15]::integer[],
		array['06125654-ad39-11f0-9804-177447a4d1ee']::uuid[],
		'A Reverse Engineering of Authorship from Reference Counts',
		'citation analysis, authorship, log analysis',
		'reviewing'
	),
	-- TOK-2025-004 is pre-staged for manually testing the mark-submission-done
	-- flow. As editor@uni.edu, visiting this submission shows the Mark done
	-- button already ENABLED: the AE and Reviewer assignments are approved AND
	-- completed, leaving only the editor's own priority-0 assignment to be
	-- compensated as part of the mark-done action itself. Clicking it
	-- compensates the editor (1 token) and flips status to done.
	(
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c15',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'TOK-2025-004',
		null,
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		array['b8a805bf-0aae-4443-9185-de019a8715cb']::uuid[],
		array[15]::integer[],
		array['06125654-ad39-11f0-9804-177447a4d1ee']::uuid[],
		'On the Impossibility of Knowing Whether a Review Was Read',
		'epistemology, reader response',
		'reviewing'
	);

insert into
	public.assignments (
		id,
		venue,
		submission,
		scholar,
		role,
		bid,
		approved,
		completed
	)
values
	(
		'c61b2e1e-ad3a-11f0-9806-5f4e3b2c1d99',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c12',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac99',
		false,
		true,
		false
	),
	(
		'c61b2e1e-ad3a-11f0-9806-5f4e3b2c1d34',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c12',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		false,
		true,
		false
	),
	(
		'fefed1e4-ad3a-11f0-9807-1f8d6e4b5c23',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c12',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		false
	),
	-- r4 (Manny Script) and r5 (Anne Notation) bid as Reviewer on TOK-2025-001,
	-- giving ae@uni.edu (Associate Editor / approver of Reviewer) bids to act on.
	(
		'fefed1e4-ad3a-11f0-9807-1f8d6e4b5c24',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c12',
		'7ff8621a-cbe0-4789-bbee-f008d38c4aca',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		true,
		false,
		false
	),
	(
		'fefed1e4-ad3a-11f0-9807-1f8d6e4b5c25',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c12',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		true,
		false,
		false
	),
	-- Usability testing setup for ae@uni.edu reviewing the "completed review"
	-- flows on TOK-2025-002:
	--   1. ae@uni.edu is approved as the Associate Editor of TOK-2025-002, so
	--      they have the approver gate for the Reviewer role on that submission.
	--   2. r2 (Sue Pervisor) has an assignment shaped like one created by
	--      `requestCompensation`: bid=false, approved=false, completed=false.
	--      This simulates the scenario where a reviewer reported completing
	--      work in an external system and asked for compensation, and the AE
	--      now has to approve the assignment before they can mark it complete
	--      and generate the compensation transaction.
	--   Compare against TOK-2025-001, where r1 is already an approved Reviewer
	--   (assignment fefed1e4-...c23) — that submission exercises the other
	--   case, where the approver already knows the work was completed elsewhere
	--   and can immediately click Complete to generate compensation.
	(
		'fefed1e4-ad3a-11f0-9807-1f8d6e4b5c26',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c13',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		false,
		true,
		false
	),
	(
		'fefed1e4-ad3a-11f0-9807-1f8d6e4b5c27',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c13',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac8',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		false,
		false
	),
	-- TOK-2025-004: assignment fixture used by both the manual mark-done flow
	-- and the over-cap demo (#126). The AE assignment is already approved AND
	-- completed; r1's Reviewer assignment is approved but UNCOMPLETED so r1
	-- counts as 2 active (with -001 too) against their cap of 1 → shows
	-- "2 / 1" in red. The editor's own priority-0 assignment is approved but
	-- uncompleted. To exercise mark-done manually: click Complete on r1's
	-- reviewer row first, then Mark done becomes enabled and compensates the
	-- editor in one action.
	(
		'fefed1e4-ad3a-11f0-9807-1f8d6e4b5c28',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c15',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac99',
		false,
		true,
		false
	),
	(
		'fefed1e4-ad3a-11f0-9807-1f8d6e4b5c29',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c15',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		false,
		true,
		true
	),
	(
		'fefed1e4-ad3a-11f0-9807-1f8d6e4b5c2a',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c15',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		false
	),
	-- Pre-staged for manually testing the over-cap load indicator (#126).
	-- Sai Entist (r3) is approved as Reviewer on TOK-2025-003 and ALSO has a
	-- pending bid as Reviewer on TOK-2025-002. With papers cap = 1 (set
	-- below), the bid row on TOK-2025-002 renders as "1 / 1" in over-cap red,
	-- and approving it triggers the warn-style confirm.
	(
		'00000000-0000-0000-0000-000000000126',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c14',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac9',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		false
	),
	(
		'00000000-0000-0000-0000-000000000226',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c13',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac9',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		true,
		false,
		false
	);

-- Cap r1 and r3 on the Reviewer role at 1 paper, so the load indicator on the
-- submission detail page renders over-cap warnings against their existing
-- approved assignments. r1 (2 active Reviewer assignments) reads "2 / 1" red
-- on TOK-2025-001 and TOK-2025-004; r3 (1 active + 1 bid) reads "1 / 1" red
-- on TOK-2025-002's bid row. See #126.
update public.volunteers
set
	papers=1
where
	roleid='f3209eee-ad37-11f0-a9a2-7ba7c65d0a81'
	and scholarid in (
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac9'
	);

--------------------------------------
-- ORCID profile mirror
--
-- Seeded rather than fetched: `npm run start:test` excludes the edge runtime, so the
-- `orcid` function cannot run and nothing here reaches the network. That is deliberate --
-- a test suite whose assertions depend on a third party's API is a suite that goes red
-- when that third party has a bad afternoon.
--
-- Three shapes, because the interesting cases are the empty ones:
--   Rigor Russ  -- a full record, for asserting the section renders
--   Reese Urcher -- a row that was READ and found to hold nothing public, which must
--                   render as nothing rather than as a heading with blanks under it
--   everyone else -- no row at all, the cold-cache case, which must render as nothing
--                   AND must not break the page
insert into
	public.orcid_profiles (
		scholar,
		orcid,
		employment_role,
		employment_department,
		employment_organization,
		education_role,
		education_organization,
		education_year,
		keywords,
		works,
		work_count,
		work_first_year,
		work_last_year,
		links,
		fetched_at,
		works_fetched_at,
		fetch_status
	)
values
	(
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
		'0000-0001-2345-6789',
		'Professor',
		'Department of Rigor',
		'University of Test',
		'Ph.D. Reproducibility',
		'Institute of Test',
		2009,
		array[
			'peer review',
			'research methods',
			'reproducibility'
		],
		'[
			{"title":"On the Reproducibility of Reviewing","year":2025,"journal":"Journal of Rigor","doi":"10.1234/rigor.2025","url":"https://doi.org/10.1234/rigor.2025"},
			{"title":"Measuring Reviewer Load","year":2023,"journal":"Journal of Rigor","doi":"10.1234/load.2023","url":"https://doi.org/10.1234/load.2023"},
			{"title":"A Theory of Token Economies","year":2021,"journal":null,"doi":null,"url":null}
		]'::jsonb,
		37,
		2009,
		2025,
		'[{"kind":"url","label":"Faculty website","value":"https://example.test/rigor","url":"https://example.test/rigor"}]'::jsonb,
		now(),
		now(),
		'ok'
	),
	(
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac8',
		'0000-0001-2345-6790',
		null,
		null,
		null,
		null,
		null,
		null,
		'{}',
		'[]'::jsonb,
		null,
		null,
		null,
		'[]'::jsonb,
		now(),
		null,
		'ok'
	);

--------------------------------------
-- A community, rather than a cast of nine
--
-- Everything above is the smallest database that makes the app work. Everything
-- below is the amount of it you need to JUDGE the app: rosters long enough to
-- scroll, expertise varied enough that the keyword chips rank into something,
-- submissions in more than one state, and a ledger with a history instead of six
-- rows stamped the same afternoon.
--
-- Nothing down here is load-bearing for a test. It is deliberately additive: no
-- row below changes a count, a balance or an assignment that anything above
-- depends on. In particular it adds NO steward, NO venue admin, NO minter, and
-- no accepted active holder of the priority-0 Editor role, each of which the
-- suite assumes there is exactly one of.
--------------------------------------
-- The scholars. Inserted set-wise rather than as one 36-column literal apiece
-- (the pattern scripts/scale-fixture.sql uses), because fifteen more copies of
-- the block at the top of this file would be most of the file. The
-- on_auth_user_created trigger reads `orcid` and `name` out of raw_user_meta_data
-- and writes the public.scholars row itself, so that is where the identity goes.
insert into
	auth.users (
		instance_id,
		id,
		aud,
		role,
		email,
		encrypted_password,
		email_confirmed_at,
		last_sign_in_at,
		raw_app_meta_data,
		raw_user_meta_data,
		created_at,
		updated_at,
		confirmation_token,
		recovery_token,
		email_change_token_new,
		email_change,
		is_super_admin,
		is_sso_user,
		is_anonymous
	)
values
	(
		'00000000-0000-0000-0000-000000000000',
		'f0000000-ad50-11f0-9000-000000000001',
		'authenticated',
		'authenticated',
		'r.eree@uni.edu',
		extensions.crypt ('password', extensions.gen_salt ('bf')),
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'{"provider":"email","providers":["email"]}',
		'{"sub": "f0000000-ad50-11f0-9000-000000000001", "orcid": "0000-0001-2346-0001", "name": "Ref Eree", "email": "r.eree@uni.edu", "email_verified": true, "phone_verified": false}',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'',
		'',
		'',
		'',
		false,
		false,
		false
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'f0000000-ad50-11f0-9000-000000000002',
		'authenticated',
		'authenticated',
		'e.bargo@uni.edu',
		extensions.crypt ('password', extensions.gen_salt ('bf')),
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'{"provider":"email","providers":["email"]}',
		'{"sub": "f0000000-ad50-11f0-9000-000000000002", "orcid": "0000-0001-2346-0002", "name": "Em Bargo", "email": "e.bargo@uni.edu", "email_verified": true, "phone_verified": false}',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'',
		'',
		'',
		'',
		false,
		false,
		false
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'f0000000-ad50-11f0-9000-000000000003',
		'authenticated',
		'authenticated',
		'p.print@uni.edu',
		extensions.crypt ('password', extensions.gen_salt ('bf')),
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'{"provider":"email","providers":["email"]}',
		'{"sub": "f0000000-ad50-11f0-9000-000000000003", "orcid": "0000-0001-2346-0003", "name": "Perry Print", "email": "p.print@uni.edu", "email_verified": true, "phone_verified": false}',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'',
		'',
		'',
		'',
		false,
		false,
		false
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'f0000000-ad50-11f0-9000-000000000004',
		'authenticated',
		'authenticated',
		'a.stract@uni.edu',
		extensions.crypt ('password', extensions.gen_salt ('bf')),
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'{"provider":"email","providers":["email"]}',
		'{"sub": "f0000000-ad50-11f0-9000-000000000004", "orcid": "0000-0001-2346-0004", "name": "Abe Stract", "email": "a.stract@uni.edu", "email_verified": true, "phone_verified": false}',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'',
		'',
		'',
		'',
		false,
		false,
		false
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'f0000000-ad50-11f0-9000-000000000005',
		'authenticated',
		'authenticated',
		'r.buttal@uni.edu',
		extensions.crypt ('password', extensions.gen_salt ('bf')),
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'{"provider":"email","providers":["email"]}',
		'{"sub": "f0000000-ad50-11f0-9000-000000000005", "orcid": "0000-0001-2346-0005", "name": "Rex Buttal", "email": "r.buttal@uni.edu", "email_verified": true, "phone_verified": false}',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'',
		'',
		'',
		'',
		false,
		false,
		false
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'f0000000-ad50-11f0-9000-000000000006',
		'authenticated',
		'authenticated',
		'o.access@uni.edu',
		extensions.crypt ('password', extensions.gen_salt ('bf')),
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'{"provider":"email","providers":["email"]}',
		'{"sub": "f0000000-ad50-11f0-9000-000000000006", "orcid": "0000-0001-2346-0006", "name": "Owen Access", "email": "o.access@uni.edu", "email_verified": true, "phone_verified": false}',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'',
		'',
		'',
		'',
		false,
		false,
		false
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'f0000000-ad50-11f0-9000-000000000007',
		'authenticated',
		'authenticated',
		'e.size@uni.edu',
		extensions.crypt ('password', extensions.gen_salt ('bf')),
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'{"provider":"email","providers":["email"]}',
		'{"sub": "f0000000-ad50-11f0-9000-000000000007", "orcid": "0000-0001-2346-0007", "name": "Effie Size", "email": "e.size@uni.edu", "email_verified": true, "phone_verified": false}',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'',
		'',
		'',
		'',
		false,
		false,
		false
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'f0000000-ad50-11f0-9000-000000000008',
		'authenticated',
		'authenticated',
		'n.hypothesis@uni.edu',
		extensions.crypt ('password', extensions.gen_salt ('bf')),
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'{"provider":"email","providers":["email"]}',
		'{"sub": "f0000000-ad50-11f0-9000-000000000008", "orcid": "0000-0001-2346-0008", "name": "Nell Hypothesis", "email": "n.hypothesis@uni.edu", "email_verified": true, "phone_verified": false}',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'',
		'',
		'',
		'',
		false,
		false,
		false
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'f0000000-ad50-11f0-9000-000000000009',
		'authenticated',
		'authenticated',
		'l.revue@uni.edu',
		extensions.crypt ('password', extensions.gen_salt ('bf')),
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'{"provider":"email","providers":["email"]}',
		'{"sub": "f0000000-ad50-11f0-9000-000000000009", "orcid": "0000-0001-2346-0009", "name": "Lita Revue", "email": "l.revue@uni.edu", "email_verified": true, "phone_verified": false}',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'',
		'',
		'',
		'',
		false,
		false,
		false
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'f0000000-ad50-11f0-9000-000000000010',
		'authenticated',
		'authenticated',
		't.yure@uni.edu',
		extensions.crypt ('password', extensions.gen_salt ('bf')),
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'{"provider":"email","providers":["email"]}',
		'{"sub": "f0000000-ad50-11f0-9000-000000000010", "orcid": "0000-0001-2346-0010", "name": "Ten Yure", "email": "t.yure@uni.edu", "email_verified": true, "phone_verified": false}',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'',
		'',
		'',
		'',
		false,
		false,
		false
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'f0000000-ad50-11f0-9000-000000000011',
		'authenticated',
		'authenticated',
		'c.spondence@uni.edu',
		extensions.crypt ('password', extensions.gen_salt ('bf')),
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'{"provider":"email","providers":["email"]}',
		'{"sub": "f0000000-ad50-11f0-9000-000000000011", "orcid": "0000-0001-2346-0011", "name": "Cora Spondence", "email": "c.spondence@uni.edu", "email_verified": true, "phone_verified": false}',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'',
		'',
		'',
		'',
		false,
		false,
		false
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'f0000000-ad50-11f0-9000-000000000012',
		'authenticated',
		'authenticated',
		's.tation@uni.edu',
		extensions.crypt ('password', extensions.gen_salt ('bf')),
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'{"provider":"email","providers":["email"]}',
		'{"sub": "f0000000-ad50-11f0-9000-000000000012", "orcid": "0000-0001-2346-0012", "name": "Sy Tation", "email": "s.tation@uni.edu", "email_verified": true, "phone_verified": false}',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'',
		'',
		'',
		'',
		false,
		false,
		false
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'f0000000-ad50-11f0-9000-000000000013',
		'authenticated',
		'authenticated',
		'p.freed@uni.edu',
		extensions.crypt ('password', extensions.gen_salt ('bf')),
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'{"provider":"email","providers":["email"]}',
		'{"sub": "f0000000-ad50-11f0-9000-000000000013", "orcid": "0000-0001-2346-0013", "name": "Prue Freed", "email": "p.freed@uni.edu", "email_verified": true, "phone_verified": false}',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'',
		'',
		'',
		'',
		false,
		false,
		false
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'f0000000-ad50-11f0-9000-000000000014',
		'authenticated',
		'authenticated',
		'e.barr@uni.edu',
		extensions.crypt ('password', extensions.gen_salt ('bf')),
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'{"provider":"email","providers":["email"]}',
		'{"sub": "f0000000-ad50-11f0-9000-000000000014", "orcid": "0000-0001-2346-0014", "name": "Errol Barr", "email": "e.barr@uni.edu", "email_verified": true, "phone_verified": false}',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'',
		'',
		'',
		'',
		false,
		false,
		false
	),
	(
		'00000000-0000-0000-0000-000000000000',
		'f0000000-ad50-11f0-9000-000000000015',
		'authenticated',
		'authenticated',
		's.batical@uni.edu',
		extensions.crypt ('password', extensions.gen_salt ('bf')),
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'{"provider":"email","providers":["email"]}',
		'{"sub": "f0000000-ad50-11f0-9000-000000000015", "orcid": "0000-0001-2346-0015", "name": "Sab Batical", "email": "s.batical@uni.edu", "email_verified": true, "phone_verified": false}',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'',
		'',
		'',
		'',
		false,
		false,
		false
	);

-- The identity row the email provider expects, one per account, matching the
-- shape of the nine above.
insert into
	auth.identities (
		provider_id,
		user_id,
		identity_data,
		provider,
		last_sign_in_at,
		created_at,
		updated_at,
		id
	)
values
	(
		'f0000000-ad50-11f0-9000-000000000001',
		'f0000000-ad50-11f0-9000-000000000001',
		'{"sub": "f0000000-ad50-11f0-9000-000000000001", "email": "r.eree@uni.edu", "email_verified": true, "phone_verified": false}',
		'email',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'f0000009-ad50-11f0-9000-000000000001'
	),
	(
		'f0000000-ad50-11f0-9000-000000000002',
		'f0000000-ad50-11f0-9000-000000000002',
		'{"sub": "f0000000-ad50-11f0-9000-000000000002", "email": "e.bargo@uni.edu", "email_verified": true, "phone_verified": false}',
		'email',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'f0000009-ad50-11f0-9000-000000000002'
	),
	(
		'f0000000-ad50-11f0-9000-000000000003',
		'f0000000-ad50-11f0-9000-000000000003',
		'{"sub": "f0000000-ad50-11f0-9000-000000000003", "email": "p.print@uni.edu", "email_verified": true, "phone_verified": false}',
		'email',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'f0000009-ad50-11f0-9000-000000000003'
	),
	(
		'f0000000-ad50-11f0-9000-000000000004',
		'f0000000-ad50-11f0-9000-000000000004',
		'{"sub": "f0000000-ad50-11f0-9000-000000000004", "email": "a.stract@uni.edu", "email_verified": true, "phone_verified": false}',
		'email',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'f0000009-ad50-11f0-9000-000000000004'
	),
	(
		'f0000000-ad50-11f0-9000-000000000005',
		'f0000000-ad50-11f0-9000-000000000005',
		'{"sub": "f0000000-ad50-11f0-9000-000000000005", "email": "r.buttal@uni.edu", "email_verified": true, "phone_verified": false}',
		'email',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'f0000009-ad50-11f0-9000-000000000005'
	),
	(
		'f0000000-ad50-11f0-9000-000000000006',
		'f0000000-ad50-11f0-9000-000000000006',
		'{"sub": "f0000000-ad50-11f0-9000-000000000006", "email": "o.access@uni.edu", "email_verified": true, "phone_verified": false}',
		'email',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'f0000009-ad50-11f0-9000-000000000006'
	),
	(
		'f0000000-ad50-11f0-9000-000000000007',
		'f0000000-ad50-11f0-9000-000000000007',
		'{"sub": "f0000000-ad50-11f0-9000-000000000007", "email": "e.size@uni.edu", "email_verified": true, "phone_verified": false}',
		'email',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'f0000009-ad50-11f0-9000-000000000007'
	),
	(
		'f0000000-ad50-11f0-9000-000000000008',
		'f0000000-ad50-11f0-9000-000000000008',
		'{"sub": "f0000000-ad50-11f0-9000-000000000008", "email": "n.hypothesis@uni.edu", "email_verified": true, "phone_verified": false}',
		'email',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'f0000009-ad50-11f0-9000-000000000008'
	),
	(
		'f0000000-ad50-11f0-9000-000000000009',
		'f0000000-ad50-11f0-9000-000000000009',
		'{"sub": "f0000000-ad50-11f0-9000-000000000009", "email": "l.revue@uni.edu", "email_verified": true, "phone_verified": false}',
		'email',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'f0000009-ad50-11f0-9000-000000000009'
	),
	(
		'f0000000-ad50-11f0-9000-000000000010',
		'f0000000-ad50-11f0-9000-000000000010',
		'{"sub": "f0000000-ad50-11f0-9000-000000000010", "email": "t.yure@uni.edu", "email_verified": true, "phone_verified": false}',
		'email',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'f0000009-ad50-11f0-9000-000000000010'
	),
	(
		'f0000000-ad50-11f0-9000-000000000011',
		'f0000000-ad50-11f0-9000-000000000011',
		'{"sub": "f0000000-ad50-11f0-9000-000000000011", "email": "c.spondence@uni.edu", "email_verified": true, "phone_verified": false}',
		'email',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'f0000009-ad50-11f0-9000-000000000011'
	),
	(
		'f0000000-ad50-11f0-9000-000000000012',
		'f0000000-ad50-11f0-9000-000000000012',
		'{"sub": "f0000000-ad50-11f0-9000-000000000012", "email": "s.tation@uni.edu", "email_verified": true, "phone_verified": false}',
		'email',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'f0000009-ad50-11f0-9000-000000000012'
	),
	(
		'f0000000-ad50-11f0-9000-000000000013',
		'f0000000-ad50-11f0-9000-000000000013',
		'{"sub": "f0000000-ad50-11f0-9000-000000000013", "email": "p.freed@uni.edu", "email_verified": true, "phone_verified": false}',
		'email',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'f0000009-ad50-11f0-9000-000000000013'
	),
	(
		'f0000000-ad50-11f0-9000-000000000014',
		'f0000000-ad50-11f0-9000-000000000014',
		'{"sub": "f0000000-ad50-11f0-9000-000000000014", "email": "e.barr@uni.edu", "email_verified": true, "phone_verified": false}',
		'email',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'f0000009-ad50-11f0-9000-000000000014'
	),
	(
		'f0000000-ad50-11f0-9000-000000000015',
		'f0000000-ad50-11f0-9000-000000000015',
		'{"sub": "f0000000-ad50-11f0-9000-000000000015", "email": "s.batical@uni.edu", "email_verified": true, "phone_verified": false}',
		'email',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'2026-01-12 09:00:00+00',
		'f0000009-ad50-11f0-9000-000000000015'
	);

-- handle_new_scholar copies only id, orcid and name, so the contact address and
-- the availability statement are set here. Every one of them says something: a
-- roster where most of the column is blank tells you nothing about how the
-- populated case reads.
update public.scholars
set
	"email"='r.eree@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Reviewing steadily. I keep a two-week turnaround and I would rather you asked me than assumed I was busy.'
where
	id='f0000000-ad50-11f0-9000-000000000001';

update public.scholars
set
	"email"='e.bargo@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Available for anything touching access and licensing. Less useful to you on statistics.'
where
	id='f0000000-ad50-11f0-9000-000000000002';

update public.scholars
set
	"email"='p.print@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Glad to review, and glad to review preprints that have already been posted — I do not think that compromises anything.'
where
	id='f0000000-ad50-11f0-9000-000000000003';

update public.scholars
set
	"email"='a.stract@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Interested in work where the writing is doing real argumentative labor, not just reporting numbers.'
where
	id='f0000000-ad50-11f0-9000-000000000004';

update public.scholars
set
	"email"='r.buttal@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Available. I write long reports and I mean them kindly; say so if that is not what you want.'
where
	id='f0000000-ad50-11f0-9000-000000000005';

update public.scholars
set
	"email"='o.access@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Associate editor. I will push authors to share data, and I will not hold a decision hostage over it.'
where
	id='f0000000-ad50-11f0-9000-000000000006';

update public.scholars
set
	"email"='e.size@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Send me the quantitative submissions. I am the person who checks whether the interval means what the abstract says it means.'
where
	id='f0000000-ad50-11f0-9000-000000000007';

update public.scholars
set
	"email"='n.hypothesis@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Available, with a standing interest in anything that failed to replicate and says so plainly.'
where
	id='f0000000-ad50-11f0-9000-000000000008';

update public.scholars
set
	"email"='l.revue@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Happy to take review articles and meta-analyses, which I notice nobody bids on.'
where
	id='f0000000-ad50-11f0-9000-000000000009';

update public.scholars
set
	"email"='t.yure@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Associate editor. Going up for promotion this year, so I am handling fewer submissions than usual and saying so up front.'
where
	id='f0000000-ad50-11f0-9000-000000000010';

update public.scholars
set
	"email"='c.spondence@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Available. I am usually the one who notices when a submission is really a comment on an earlier paper.'
where
	id='f0000000-ad50-11f0-9000-000000000011';

update public.scholars
set
	"email"='s.tation@uni.edu',
	"available"='false',
	"steward"='false',
	"status"='Stepping back from reviewing for a year. I will say when I am back rather than leaving this ambiguous.'
where
	id='f0000000-ad50-11f0-9000-000000000012';

update public.scholars
set
	"email"='p.freed@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Available and fast. I will read your supplementary material, which I gather is unusual.'
where
	id='f0000000-ad50-11f0-9000-000000000013';

update public.scholars
set
	"email"='e.barr@uni.edu',
	"available"='false',
	"steward"='false',
	"status"='Not yet decided about this venue — I would like to see how the compensation actually works in practice first.'
where
	id='f0000000-ad50-11f0-9000-000000000014';

update public.scholars
set
	"email"='s.batical@uni.edu',
	"available"='true',
	"steward"='false',
	"status"='Associate editor, on leave from teaching this year, which means I have more time for this than I normally would.'
where
	id='f0000000-ad50-11f0-9000-000000000015';

-- Volunteer records. Reviewer and Associate Editor only: the Editor role is
-- priority 0, and the suite assumes exactly one accepted, active holder of it.
-- Five of these claim no `peer review` expertise, which is what keeps that chip
-- a filter rather than a label on everything.
insert into
	public.volunteers (
		"id",
		"scholarid",
		"roleid",
		"created_at",
		"expertise",
		"active",
		"accepted"
	)
values
	(
		'f0000001-ad50-11f0-9000-000000000001',
		'f0000000-ad50-11f0-9000-000000000001',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2026-01-12 09:30:00+00',
		'peer review, research integrity, editorial process',
		'true',
		'accepted'
	),
	(
		'f0000001-ad50-11f0-9000-000000000002',
		'f0000000-ad50-11f0-9000-000000000002',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2026-01-12 09:30:00+00',
		'open access, embargoes, science communication',
		'true',
		'accepted'
	),
	(
		'f0000001-ad50-11f0-9000-000000000003',
		'f0000000-ad50-11f0-9000-000000000003',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2026-01-12 09:30:00+00',
		'preprints, open access, peer review',
		'true',
		'accepted'
	),
	(
		'f0000001-ad50-11f0-9000-000000000004',
		'f0000000-ad50-11f0-9000-000000000004',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2026-01-12 09:30:00+00',
		'science communication, qualitative methods',
		'true',
		'accepted'
	),
	(
		'f0000001-ad50-11f0-9000-000000000005',
		'f0000000-ad50-11f0-9000-000000000005',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2026-01-12 09:30:00+00',
		'peer review, research ethics, retraction',
		'true',
		'accepted'
	),
	(
		'f0000001-ad50-11f0-9000-000000000006',
		'f0000000-ad50-11f0-9000-000000000006',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		'2026-01-12 09:30:00+00',
		'open access, data sharing, peer review',
		'true',
		'accepted'
	),
	(
		'f0000001-ad50-11f0-9000-000000000007',
		'f0000000-ad50-11f0-9000-000000000007',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2026-01-12 09:30:00+00',
		'statistics, effect sizes, research methods',
		'true',
		'accepted'
	),
	(
		'f0000001-ad50-11f0-9000-000000000008',
		'f0000000-ad50-11f0-9000-000000000008',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2026-01-12 09:30:00+00',
		'statistics, replication, peer review',
		'true',
		'accepted'
	),
	(
		'f0000001-ad50-11f0-9000-000000000009',
		'f0000000-ad50-11f0-9000-000000000009',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2026-01-12 09:30:00+00',
		'peer review, bibliometrics, citation analysis',
		'true',
		'accepted'
	),
	(
		'f0000001-ad50-11f0-9000-000000000010',
		'f0000000-ad50-11f0-9000-000000000010',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		'2026-01-12 09:30:00+00',
		'research integrity, measurement, peer review',
		'true',
		'accepted'
	),
	(
		'f0000001-ad50-11f0-9000-000000000011',
		'f0000000-ad50-11f0-9000-000000000011',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2026-01-12 09:30:00+00',
		'editorial process, peer review, retraction',
		'true',
		'accepted'
	),
	(
		'f0000001-ad50-11f0-9000-000000000012',
		'f0000000-ad50-11f0-9000-000000000012',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2026-01-12 09:30:00+00',
		'bibliometrics, citation analysis',
		'false',
		'accepted'
	),
	(
		'f0000001-ad50-11f0-9000-000000000013',
		'f0000000-ad50-11f0-9000-000000000013',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2026-01-12 09:30:00+00',
		'peer review, reproducibility, research methods',
		'true',
		'accepted'
	),
	(
		'f0000001-ad50-11f0-9000-000000000014',
		'f0000000-ad50-11f0-9000-000000000014',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2026-01-12 09:30:00+00',
		'statistics, sampling, measurement',
		'false',
		'invited'
	),
	(
		'f0000001-ad50-11f0-9000-000000000015',
		'f0000000-ad50-11f0-9000-000000000015',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		'2026-01-12 09:30:00+00',
		'peer review, editorial process, qualitative methods',
		'true',
		'accepted'
	);

-- Six more ORCID mirrors. The three shapes the block above sets out still hold:
-- most of these are full records, one was read and found to hold nothing public,
-- and the scholars with no row at all are still the majority of the venue.
insert into
	public.orcid_profiles (
		scholar,
		orcid,
		employment_role,
		employment_department,
		employment_organization,
		education_role,
		education_organization,
		education_year,
		keywords,
		works,
		work_count,
		work_first_year,
		work_last_year,
		links,
		fetched_at,
		works_fetched_at,
		fetch_status
	)
values
	(
		'f0000000-ad50-11f0-9000-000000000001',
		'0000-0001-2346-0001',
		'Senior Lecturer',
		'School of Information',
		'Northgate University',
		'Ph.D. Information Science',
		'Northgate University',
		2014,
		array[
			'peer review',
			'research integrity',
			'scholarly communication'
		],
		'[
			{"title":"Referee Fatigue in Small Fields","year":2025,"journal":"Transactions on Knowledge","doi":null,"url":null},
			{"title":"What Editors Do When Nobody Bids","year":2022,"journal":"Journal of Editorial Practice","doi":null,"url":null}
		]'::jsonb,
		19,
		2014,
		2025,
		'[{"kind":"url","label":"Personal site","value":"https://example.test/eree","url":"https://example.test/eree"}]'::jsonb,
		now(),
		now(),
		'ok'
	),
	(
		'f0000000-ad50-11f0-9000-000000000003',
		'0000-0001-2346-0003',
		'Assistant Professor',
		'Department of Science and Technology Studies',
		'Bellhaven College',
		'Ph.D. Science and Technology Studies',
		'Marram University',
		2019,
		array['preprints', 'open access', 'priority disputes'],
		'[
			{"title":"The Preprint and the Postprint","year":2026,"journal":"Open Scholarship Review","doi":null,"url":null},
			{"title":"Who Gets to Be First","year":2023,"journal":null,"doi":null,"url":null}
		]'::jsonb,
		11,
		2019,
		2026,
		'[{"kind":"url","label":"Lab page","value":"https://example.test/print","url":"https://example.test/print"}]'::jsonb,
		now(),
		now(),
		'ok'
	),
	(
		'f0000000-ad50-11f0-9000-000000000007',
		'0000-0001-2346-0007',
		'Professor',
		'Department of Statistics',
		'Marram University',
		'Ph.D. Statistics',
		'Northgate University',
		2003,
		array[
			'effect sizes',
			'statistical reporting',
			'research methods'
		],
		'[
			{"title":"Intervals Nobody Reports","year":2025,"journal":"Journal of Quantitative Methods","doi":null,"url":null},
			{"title":"A Second Look at Seventeen Meta-Analyses","year":2021,"journal":"Journal of Quantitative Methods","doi":null,"url":null},
			{"title":"Teaching Uncertainty","year":2016,"journal":null,"doi":null,"url":null}
		]'::jsonb,
		64,
		2003,
		2025,
		'[{"kind":"url","label":"Faculty page","value":"https://example.test/size","url":"https://example.test/size"}]'::jsonb,
		now(),
		now(),
		'ok'
	),
	(
		'f0000000-ad50-11f0-9000-000000000009',
		'0000-0001-2346-0009',
		'Research Fellow',
		'Centre for Bibliometrics',
		'Bellhaven College',
		'Ph.D. Library and Information Science',
		'Bellhaven College',
		2021,
		array['bibliometrics', 'citation analysis'],
		'[
			{"title":"Citation Cartels Revisited","year":2026,"journal":"Transactions on Knowledge","doi":null,"url":null}
		]'::jsonb,
		7,
		2021,
		2026,
		'[]'::jsonb,
		now(),
		now(),
		'ok'
	),
	(
		'f0000000-ad50-11f0-9000-000000000015',
		'0000-0001-2346-0015',
		'Associate Professor',
		'Department of Philosophy',
		'Northgate University',
		'Ph.D. Philosophy',
		'Bellhaven College',
		2011,
		array[
			'epistemology',
			'testimony',
			'philosophy of science'
		],
		'[
			{"title":"Knowing Through Others","year":2024,"journal":"Mind and Method","doi":null,"url":null},
			{"title":"The Epistemology of Refereeing","year":2020,"journal":"Mind and Method","doi":null,"url":null}
		]'::jsonb,
		28,
		2011,
		2024,
		'[{"kind":"url","label":"Department profile","value":"https://example.test/batical","url":"https://example.test/batical"}]'::jsonb,
		now(),
		now(),
		'ok'
	),
	(
		'f0000000-ad50-11f0-9000-000000000011',
		'0000-0001-2346-0011',
		null,
		null,
		null,
		null,
		null,
		null,
		'{}',
		'[]'::jsonb,
		null,
		null,
		null,
		'[]'::jsonb,
		now(),
		null,
		'ok'
	);

-- The tokens those compensations are made of. Minted straight to the recipient,
-- exactly as the token blocks above do: a direct insert logs a MINT in
-- public.token_events, which replays consistently and which
-- end2end/global-teardown.ts tolerates. Moving existing tokens instead would
-- log unattributed MOVES, which it does not.
insert into
	public.tokens (id, currency, scholar, venue)
values
	(
		'f0000004-ad50-11f0-9000-000000000001',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4aca',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000002',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4aca',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000003',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4aca',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000004',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4aca',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000005',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4aca',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000006',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4aca',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000007',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4aca',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000008',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4aca',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000009',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4aca',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000010',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4aca',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000011',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000001',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000012',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000001',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000013',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000001',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000014',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000001',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000015',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000001',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000016',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000001',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000017',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000001',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000018',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000001',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000019',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000001',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000020',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000001',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000021',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000003',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000022',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000003',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000023',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000003',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000024',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000003',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000025',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000003',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000026',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000003',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000027',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000003',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000028',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000003',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000029',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000003',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000030',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000003',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000031',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000032',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000033',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000034',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000035',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000036',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000037',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000038',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000039',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000040',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000041',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000008',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000042',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000008',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000043',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000008',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000044',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000008',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000045',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000008',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000046',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000008',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000047',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000008',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000048',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000008',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000049',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000008',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000050',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'f0000000-ad50-11f0-9000-000000000008',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000051',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000052',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000053',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000054',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000055',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000056',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000057',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000058',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000059',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000060',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000061',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000062',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000063',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000064',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000065',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000066',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000067',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000068',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000069',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	),
	(
		'f0000004-ad50-11f0-9000-000000000070',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null
	);

-- Compensation actually paid, spread across the year, so the venue ledger reads
-- as a history rather than as one afternoon's worth of identical rows.
insert into
	public.transactions (
		"id",
		"created_at",
		"creator",
		"from_scholar",
		"from_venue",
		"to_scholar",
		"to_venue",
		"tokens",
		"currency",
		"purpose",
		"status"
	)
values
	(
		'f0000003-ad50-11f0-9000-000000000001',
		now()-interval '22 days',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'7ff8621a-cbe0-4789-bbee-f008d38c4aca',
		null,
		'{"f0000004-ad50-11f0-9000-000000000001","f0000004-ad50-11f0-9000-000000000002","f0000004-ad50-11f0-9000-000000000003","f0000004-ad50-11f0-9000-000000000004","f0000004-ad50-11f0-9000-000000000005","f0000004-ad50-11f0-9000-000000000006","f0000004-ad50-11f0-9000-000000000007","f0000004-ad50-11f0-9000-000000000008","f0000004-ad50-11f0-9000-000000000009","f0000004-ad50-11f0-9000-000000000010"}',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'Compensation for reviewing TOK-2025-005',
		'approved'
	),
	(
		'f0000003-ad50-11f0-9000-000000000002',
		now()-interval '15 days',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000000-ad50-11f0-9000-000000000001',
		null,
		'{"f0000004-ad50-11f0-9000-000000000011","f0000004-ad50-11f0-9000-000000000012","f0000004-ad50-11f0-9000-000000000013","f0000004-ad50-11f0-9000-000000000014","f0000004-ad50-11f0-9000-000000000015","f0000004-ad50-11f0-9000-000000000016","f0000004-ad50-11f0-9000-000000000017","f0000004-ad50-11f0-9000-000000000018","f0000004-ad50-11f0-9000-000000000019","f0000004-ad50-11f0-9000-000000000020"}',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'Compensation for reviewing TOK-2025-006',
		'approved'
	),
	(
		'f0000003-ad50-11f0-9000-000000000003',
		now()-interval '8 days',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000000-ad50-11f0-9000-000000000003',
		null,
		'{"f0000004-ad50-11f0-9000-000000000021","f0000004-ad50-11f0-9000-000000000022","f0000004-ad50-11f0-9000-000000000023","f0000004-ad50-11f0-9000-000000000024","f0000004-ad50-11f0-9000-000000000025","f0000004-ad50-11f0-9000-000000000026","f0000004-ad50-11f0-9000-000000000027","f0000004-ad50-11f0-9000-000000000028","f0000004-ad50-11f0-9000-000000000029","f0000004-ad50-11f0-9000-000000000030"}',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'Compensation for reviewing TOK-2025-007',
		'approved'
	),
	(
		'f0000003-ad50-11f0-9000-000000000004',
		now()-interval '2 days',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		null,
		'{"f0000004-ad50-11f0-9000-000000000031","f0000004-ad50-11f0-9000-000000000032","f0000004-ad50-11f0-9000-000000000033","f0000004-ad50-11f0-9000-000000000034","f0000004-ad50-11f0-9000-000000000035","f0000004-ad50-11f0-9000-000000000036","f0000004-ad50-11f0-9000-000000000037","f0000004-ad50-11f0-9000-000000000038","f0000004-ad50-11f0-9000-000000000039","f0000004-ad50-11f0-9000-000000000040"}',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'Compensation for handling TOK-2025-008',
		'approved'
	),
	(
		'f0000003-ad50-11f0-9000-000000000005',
		now()-interval '2 days',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000000-ad50-11f0-9000-000000000008',
		null,
		'{"f0000004-ad50-11f0-9000-000000000041","f0000004-ad50-11f0-9000-000000000042","f0000004-ad50-11f0-9000-000000000043","f0000004-ad50-11f0-9000-000000000044","f0000004-ad50-11f0-9000-000000000045","f0000004-ad50-11f0-9000-000000000046","f0000004-ad50-11f0-9000-000000000047","f0000004-ad50-11f0-9000-000000000048","f0000004-ad50-11f0-9000-000000000049","f0000004-ad50-11f0-9000-000000000050"}',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'Compensation for reviewing TOK-2025-008',
		'approved'
	),
	(
		'f0000003-ad50-11f0-9000-000000000006',
		now()-interval '1 day',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		null,
		'{"f0000004-ad50-11f0-9000-000000000051","f0000004-ad50-11f0-9000-000000000052","f0000004-ad50-11f0-9000-000000000053","f0000004-ad50-11f0-9000-000000000054","f0000004-ad50-11f0-9000-000000000055","f0000004-ad50-11f0-9000-000000000056","f0000004-ad50-11f0-9000-000000000057","f0000004-ad50-11f0-9000-000000000058","f0000004-ad50-11f0-9000-000000000059","f0000004-ad50-11f0-9000-000000000060","f0000004-ad50-11f0-9000-000000000061","f0000004-ad50-11f0-9000-000000000062","f0000004-ad50-11f0-9000-000000000063","f0000004-ad50-11f0-9000-000000000064","f0000004-ad50-11f0-9000-000000000065","f0000004-ad50-11f0-9000-000000000066","f0000004-ad50-11f0-9000-000000000067","f0000004-ad50-11f0-9000-000000000068","f0000004-ad50-11f0-9000-000000000069","f0000004-ad50-11f0-9000-000000000070"}',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'Compensation for two reviews delivered over the summer',
		'approved'
	);

-- Ten more submissions, four of them done. Until now every seeded submission was
-- `reviewing`, so the completed state -- and the venue's done_visibility window
-- -- had nothing to render. Each carries one payment per author, pointing at the
-- venue's original submission payment the way the four above do.
insert into
	public.submissions (
		id,
		venue,
		externalid,
		previousid,
		submission_type,
		authors,
		payments,
		transactions,
		title,
		expertise,
		status,
		completed_at
	)
values
	(
		'f0000002-ad50-11f0-9000-000000000005',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'TOK-2025-005',
		null,
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		array['7ff8621a-cbe0-4789-bbee-f008d38c4ac7']::uuid[],
		array[15]::integer[],
		array['06125654-ad39-11f0-9804-177447a4d1ee']::uuid[],
		'Citation Cartels and the Small Worlds That Sustain Them',
		'bibliometrics, citation analysis, network analysis',
		'done',
		now()-interval '23 days'
	),
	(
		'f0000002-ad50-11f0-9000-000000000006',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'TOK-2025-006',
		null,
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		array['b8a805bf-0aae-4443-9185-de019a8715ec']::uuid[],
		array[15]::integer[],
		array['06125654-ad39-11f0-9804-177447a4d1ee']::uuid[],
		'What Reviewers Say When They Are Told Nobody Will Read It',
		'peer review, research ethics, qualitative methods',
		'done',
		now()-interval '16 days'
	),
	(
		'f0000002-ad50-11f0-9000-000000000007',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'TOK-2025-007',
		null,
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		array[
			'f0000000-ad50-11f0-9000-000000000003',
			'b8a805bf-0aae-4443-9185-de019a8715cb'
		]::uuid[],
		array[15, 15]::integer[],
		array[
			'06125654-ad39-11f0-9804-177447a4d1ee',
			'06125654-ad39-11f0-9804-177447a4d1ee'
		]::uuid[],
		'Preprints, Priority, and the Shrinking Value of Being First',
		'preprints, open access, science communication',
		'done',
		now()-interval '9 days'
	),
	(
		'f0000002-ad50-11f0-9000-000000000008',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'TOK-2025-008',
		null,
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		array['f0000000-ad50-11f0-9000-000000000008']::uuid[],
		array[15]::integer[],
		array['06125654-ad39-11f0-9804-177447a4d1ee']::uuid[],
		'A Failure to Replicate Seventeen Findings About Replication',
		'replication, statistics, research methods',
		'done',
		now()-interval '3 days'
	),
	(
		'f0000002-ad50-11f0-9000-000000000009',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'TOK-2025-009',
		null,
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		array['f0000000-ad50-11f0-9000-000000000013']::uuid[],
		array[15]::integer[],
		array['06125654-ad39-11f0-9804-177447a4d1ee']::uuid[],
		'Who Reads the Supplementary Material?',
		'open science, data sharing, reader response',
		'reviewing',
		null
	),
	(
		'f0000002-ad50-11f0-9000-000000000010',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'TOK-2025-010',
		null,
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		array[
			'f0000000-ad50-11f0-9000-000000000011',
			'f0000000-ad50-11f0-9000-000000000005'
		]::uuid[],
		array[15, 15]::integer[],
		array[
			'06125654-ad39-11f0-9804-177447a4d1ee',
			'06125654-ad39-11f0-9804-177447a4d1ee'
		]::uuid[],
		'Retraction Notices as a Genre',
		'retraction, research integrity, science communication',
		'reviewing',
		null
	),
	(
		'f0000002-ad50-11f0-9000-000000000011',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'TOK-2025-011',
		null,
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		array['f0000000-ad50-11f0-9000-000000000009']::uuid[],
		array[15]::integer[],
		array['06125654-ad39-11f0-9804-177447a4d1ee']::uuid[],
		'Measurement Without a Referent: Impact Factors Considered as Folklore',
		'bibliometrics, measurement, history of science',
		'reviewing',
		null
	),
	(
		'f0000002-ad50-11f0-9000-000000000012',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'TOK-2025-012',
		null,
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		array['7ff8621a-cbe0-4789-bbee-f008d38c4ac8']::uuid[],
		array[15]::integer[],
		array['06125654-ad39-11f0-9804-177447a4d1ee']::uuid[],
		'Testimony, Trust, and the Limits of Reviewing Outside Your Field',
		'testimony, peer review, epistemology',
		'reviewing',
		null
	),
	(
		'f0000002-ad50-11f0-9000-000000000013',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'TOK-2025-013',
		null,
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		array[
			'f0000000-ad50-11f0-9000-000000000014',
			'f0000000-ad50-11f0-9000-000000000007'
		]::uuid[],
		array[15, 15]::integer[],
		array[
			'06125654-ad39-11f0-9804-177447a4d1ee',
			'06125654-ad39-11f0-9804-177447a4d1ee'
		]::uuid[],
		'Sampling Frames in Studies of Scholarly Behavior',
		'sampling, statistics, research methods',
		'reviewing',
		null
	),
	(
		'f0000002-ad50-11f0-9000-000000000014',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'TOK-2025-014',
		null,
		'17ca2095-e231-4d5e-a9be-95c7de79a9a5',
		array['b8a805bf-0aae-4443-9185-de019a8715cb']::uuid[],
		array[15]::integer[],
		array['06125654-ad39-11f0-9804-177447a4d1ee']::uuid[],
		'An Argument That Peer Review Cannot Be Studied by Peer Review',
		'peer review, epistemology, philosophy of science',
		'reviewing',
		null
	);

-- Staffing for the ten submissions above: an editor, an associate editor and two
-- referees each, so their detail pages render a full assignment table. The
-- referees are drawn from the Reviewer roster rather than repeated, so the
-- per-scholar load indicators differ from one another.
insert into
	public.assignments (
		id,
		venue,
		submission,
		scholar,
		role,
		bid,
		approved,
		completed
	)
values
	(
		'f0000005-ad50-11f0-9000-000000000001',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000005',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac99',
		false,
		true,
		true
	),
	(
		'f0000005-ad50-11f0-9000-000000000002',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000005',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		false,
		true,
		true
	),
	(
		'f0000005-ad50-11f0-9000-000000000003',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000005',
		'f0000000-ad50-11f0-9000-000000000005',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		true
	),
	(
		'f0000005-ad50-11f0-9000-000000000004',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000005',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac8',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		true
	),
	(
		'f0000005-ad50-11f0-9000-000000000005',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000006',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac99',
		false,
		true,
		true
	),
	(
		'f0000005-ad50-11f0-9000-000000000006',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000006',
		'f0000000-ad50-11f0-9000-000000000006',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		false,
		true,
		true
	),
	(
		'f0000005-ad50-11f0-9000-000000000007',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000006',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		true
	),
	(
		'f0000005-ad50-11f0-9000-000000000008',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000006',
		'f0000000-ad50-11f0-9000-000000000001',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		true
	),
	(
		'f0000005-ad50-11f0-9000-000000000009',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000007',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac99',
		false,
		true,
		true
	),
	(
		'f0000005-ad50-11f0-9000-000000000010',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000007',
		'f0000000-ad50-11f0-9000-000000000010',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		false,
		true,
		true
	),
	(
		'f0000005-ad50-11f0-9000-000000000011',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000007',
		'f0000000-ad50-11f0-9000-000000000011',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		true
	),
	(
		'f0000005-ad50-11f0-9000-000000000012',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000007',
		'f0000000-ad50-11f0-9000-000000000005',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		true
	),
	(
		'f0000005-ad50-11f0-9000-000000000013',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000008',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac99',
		false,
		true,
		true
	),
	(
		'f0000005-ad50-11f0-9000-000000000014',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000008',
		'f0000000-ad50-11f0-9000-000000000015',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		false,
		true,
		true
	),
	(
		'f0000005-ad50-11f0-9000-000000000015',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000008',
		'f0000000-ad50-11f0-9000-000000000007',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		true
	),
	(
		'f0000005-ad50-11f0-9000-000000000016',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000008',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac8',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		true
	),
	(
		'f0000005-ad50-11f0-9000-000000000017',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000009',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac99',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000018',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000009',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000019',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000009',
		'f0000000-ad50-11f0-9000-000000000009',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000020',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000009',
		'f0000000-ad50-11f0-9000-000000000011',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000021',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000010',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac99',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000022',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000010',
		'f0000000-ad50-11f0-9000-000000000006',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000023',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000010',
		'f0000000-ad50-11f0-9000-000000000013',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000024',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000010',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000025',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000011',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac99',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000026',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000011',
		'f0000000-ad50-11f0-9000-000000000010',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000027',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000011',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac8',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000028',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000011',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000029',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000012',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac99',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000030',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000012',
		'f0000000-ad50-11f0-9000-000000000015',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000031',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000012',
		'f0000000-ad50-11f0-9000-000000000001',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000032',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000012',
		'f0000000-ad50-11f0-9000-000000000003',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000033',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000013',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac99',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000034',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000013',
		'b8a805bf-0aae-4443-9185-de019a8715db',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000035',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000013',
		'f0000000-ad50-11f0-9000-000000000005',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000036',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000013',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000037',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000014',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac99',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000038',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000014',
		'f0000000-ad50-11f0-9000-000000000006',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000039',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000014',
		'f0000000-ad50-11f0-9000-000000000008',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		false
	),
	(
		'f0000005-ad50-11f0-9000-000000000040',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000002-ad50-11f0-9000-000000000014',
		'f0000000-ad50-11f0-9000-000000000009',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		false,
		true,
		false
	);

-- The venue's bid vocabulary. The table was empty, which meant every bid in the
-- seed was an undifferentiated "yes" and the preference column had nothing in
-- it. end2end/preferences.end.ts clears these before it runs and restores them
-- after, so seeding them costs that spec nothing.
insert into
	public.preference_levels (id, venueid, label, rank)
values
	(
		'f0000006-ad50-11f0-9000-000000000001',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'Preferred',
		0
	),
	(
		'f0000006-ad50-11f0-9000-000000000002',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'If necessary',
		1
	),
	(
		'f0000006-ad50-11f0-9000-000000000003',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'No',
		2
	);

-- Thank-you notes, in all three states the vetting lifecycle has. The table was
-- empty, so the author's view, the editor's vetting queue and the reviewer's
-- delivered note were all unreachable without writing one by hand first.
insert into
	public.thanks (
		id,
		submission,
		venue,
		author,
		message,
		status,
		approver,
		decline_reason,
		created_at
	)
values
	(
		'f0000007-ad50-11f0-9000-000000000001',
		'f0000002-ad50-11f0-9000-000000000005',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
		'Whoever read this one: you caught an error in the second model that I had walked past four times. The paper is materially better for it. Thank you.',
		'approved',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		null,
		now()-interval '21 days'
	),
	(
		'f0000007-ad50-11f0-9000-000000000002',
		'f0000002-ad50-11f0-9000-000000000006',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'b8a805bf-0aae-4443-9185-de019a8715ec',
		'Three careful reports inside a month, on a paper that argues with most of the field. I did not expect that and I am grateful for it.',
		'proposed',
		null,
		null,
		now()-interval '14 days'
	),
	(
		'f0000007-ad50-11f0-9000-000000000003',
		'f0000002-ad50-11f0-9000-000000000008',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'f0000000-ad50-11f0-9000-000000000008',
		'Thanks to reviewer 2 in particular, who I am fairly sure is the person who reviewed my last submission as well.',
		'declined',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'Kindly meant, but it speculates about who a referee was, which is exactly what the note must not do. Happy to pass on a version without the last clause.',
		now()-interval '1 day'
	);

-- Endorsements on the venue proposal. Also empty until now, so the proposal page
-- showed a petition nobody had signed.
insert into
	public.supporters (id, scholarid, message, proposalid, created_at)
values
	(
		'f0000008-ad50-11f0-9000-000000000001',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac8',
		'I have refereed for this venue for six years without being asked once whether I had the time. Worth trying something else.',
		'82246928-ad37-11f0-a071-bb5db9b6e698',
		'2026-01-20 11:00:00+00'
	),
	(
		'f0000008-ad50-11f0-9000-000000000002',
		'f0000000-ad50-11f0-9000-000000000007',
		'Supportive, with one reservation: the compensation has to be visible to authors or it will read as a fee.',
		'82246928-ad37-11f0-a071-bb5db9b6e698',
		'2026-01-21 09:30:00+00'
	),
	(
		'f0000008-ad50-11f0-9000-000000000003',
		'f0000000-ad50-11f0-9000-000000000015',
		'Yes.',
		'82246928-ad37-11f0-a071-bb5db9b6e698',
		'2026-01-21 16:45:00+00'
	),
	(
		'f0000008-ad50-11f0-9000-000000000004',
		'7ff8621a-cbe0-4789-bbee-f008d38c4acb',
		'',
		'82246928-ad37-11f0-a071-bb5db9b6e698',
		'2026-01-23 14:05:00+00'
	);
