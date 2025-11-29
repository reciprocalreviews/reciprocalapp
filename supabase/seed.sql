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
		'rigor@college.edu',
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
		'{"sub": "7ff8621a-cbe0-4789-bbee-f008d38c4ac7", "email": "rigor@college.edu", "email_verified": true, "phone_verified": false}',
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
		'foot@institute.edu',
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
		'{"sub": "b8a805bf-0aae-4443-9185-de019a8715cb", "email": "foot@institute.edu", "email_verified": true, "phone_verified": false}',
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
		'scholar@uni.edu',
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
		'{"sub": "d181d165-8b6a-4d79-ad28-a9aece21d813", "email": "scholar@uni.edu", "email_verified": true, "phone_verified": false}',
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
		'{"sub": "7ff8621a-cbe0-4789-bbee-f008d38c4ac7", "email": "rigor@college.edu", "email_verified": false, "phone_verified": false}',
		'email',
		'2025-10-19 22:00:38.375679+00',
		'2025-10-19 22:00:38.375695+00',
		'2025-10-19 22:00:38.375695+00',
		'24f92ade-b454-4757-945e-cc7e3805390d'
	),
	(
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		'{"sub": "b8a805bf-0aae-4443-9185-de019a8715cb", "email": "foot@institute.edu", "email_verified": false, "phone_verified": false}',
		'email',
		'2025-10-19 22:01:42.358867+00',
		'2025-10-19 22:01:42.358883+00',
		'2025-10-19 22:01:42.358883+00',
		'c221be80-1e04-4664-b8d3-0ef407ee6a85'
	),
	(
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
		'{"sub": "d181d165-8b6a-4d79-ad28-a9aece21d813", "email": "scholar@uni.edu", "email_verified": false, "phone_verified": false}',
		'email',
		'2025-10-19 21:59:30.449912+00',
		'2025-10-19 21:59:30.449967+00',
		'2025-10-19 21:59:30.449967+00',
		'd03732ca-fa0b-409c-ac8f-5c0aaa035b14'
	);

insert into
	public.currencies (id, name, description, minters)
values
	(
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'ACM TOCE currency',
		'',
		'{"7ff8621a-cbe0-4789-bbee-f008d38c4ac7"}'
	);

update public.scholars
set
	orcid='0000-0001-2345-6780',
	"name"='Rigor Russ',
	"email"='rigor@college.edu',
	"available"='true',
	"steward"='false'
where
	id='7ff8621a-cbe0-4789-bbee-f008d38c4ac7';

update public.scholars
set
	orcid='0000-0001-2345-6781',
	"name"='Foot Note',
	"email"='foot@institute.edu',
	"available"='true',
	"steward"='false',
	"status"='I can review as many things as you send me!'
where
	id='b8a805bf-0aae-4443-9185-de019a8715cb';

update public.scholars
set
	orcid='0000-0001-2345-6782',
	"name"='Scholar Lee',
	"email"='scholar@uni.edu',
	"available"='true',
	"steward"='true'
where
	id='d181d165-8b6a-4d79-ad28-a9aece21d813';

insert into
	public.venues (
		"id",
		"title",
		"description",
		"url",
		"currency",
		"welcome_amount",
		"edit_amount",
		"submission_cost",
		"editors"
	)
values
	(
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'Transactions on Knowledge',
		'This is a mock venue, for local testing. It accepts any fake submissions that the developers want to submit, on any topic, as long as it helps them ensure the platform is functioning correctly and reflects the needs of the community. Have any idea for how to improve the platform? Submit to the actual editors, not this fake venue instance.',
		'https://tok.science.org',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'20',
		'1',
		'10',
		'{"d181d165-8b6a-4d79-ad28-a9aece21d813"}'
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
		'{"scholar@uni.edu"}',
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
		"amount",
		"priority"
	)
values
	(
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'Associate Editor',
		'Invites reviewers and makes recommendations.',
		'true',
		'false',
		null,
		'10',
		'0'
	),
	(
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'Reviewer',
		'Evaluates a submission.',
		'false',
		'true',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		'10',
		'0'
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
		'ec74db86-ad38-11f0-97f1-8bcd8f9c8254',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74dc3a-ad38-11f0-97f2-f39915e62804',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74dc6c-ad38-11f0-97f3-6fe2b890b86c',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74dc9e-ad38-11f0-97f4-07fb88341648',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74dcd0-ad38-11f0-97f5-73d10c3cf0e2',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74dcf8-ad38-11f0-97f6-033df7b8246c',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74dd20-ad38-11f0-97f7-1776b16e0855',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74de7e-ad38-11f0-97f8-6392d6dffa33',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74df00-ad38-11f0-97f9-f310de92543e',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74df32-ad38-11f0-97fa-13316bd5a967',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74df82-ad38-11f0-97fb-1744e83622a7',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74dfb4-ad38-11f0-97fc-979f820dc15f',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74dfdc-ad38-11f0-97fd-fb653a615af7',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74e004-ad38-11f0-97fe-57efeb37df3a',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		null
	),
	(
		'ec74e036-ad38-11f0-97ff-9b4690da85ed',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6'
	),
	(
		'ec74e05e-ad38-11f0-9800-6fcd74da877e',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6'
	),
	(
		'ec74e086-ad38-11f0-9801-7f99e92ce9a0',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6'
	),
	(
		'ec74e0b8-ad38-11f0-9802-3f3bd3aa0e75',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6'
	),
	(
		'ec74e0e0-ad38-11f0-9803-cf3d40db77f3',
		'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac',
		null,
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6'
	);

insert into
	public.volunteers (
		"id",
		"scholarid",
		"roleid",
		"created",
		"expertise",
		"active",
		"accepted"
	)
values
	(
		'f9bfb99c-ad37-11f0-83e8-875a9c9887b5',
		'7ff8621a-cbe0-4789-bbee-f008d38c4ac7',
		'ed5e1cd4-ad37-11f0-83e7-8742b968ac75',
		'2025-10-19 22:07:17.336976+00',
		'',
		'true',
		'accepted'
	),
	(
		'fefccf8a-ad37-11f0-a9a3-7bcd0d5d1666',
		'b8a805bf-0aae-4443-9185-de019a8715cb',
		'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81',
		'2025-10-19 22:07:26.125662+00',
		'',
		'true',
		'accepted'
	);

insert into
	public.transactions (
		"id",
		"created",
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
	);

insert into
	public.submissions (
		id,
		venue,
		externalid,
		previousid,
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
		array['b8a805bf-0aae-4443-9185-de019a8715cb']::uuid[],
		array[15]::integer[],
		array['06125654-ad39-11f0-9804-177447a4d1ee']::uuid[],
		'A Study on the Effectiveness of Peer Review Incentives in Academic Publishing',
		'Peer review, academic publishing, field study',
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
		'c61b2e1e-ad3a-11f0-9806-5f4e3b2c1d34',
		'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6',
		'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c12',
		'd181d165-8b6a-4d79-ad28-a9aece21d813',
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
	);
