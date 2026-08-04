-- Emits one JSON object describing the state a backup captured, so a restore can
-- be *checked* rather than assumed. Consumed by supabase/dr/dump.sh, which folds
-- it into manifest.json alongside the file checksums.
--
-- Written defensively on purpose. `token_events`, `audit_log`, and
-- `transactions.seq` do not exist yet — they arrive with the ledger phase — so
-- every table and column is probed before it is read. A manifest taken before
-- that phase simply omits those keys rather than failing, and a manifest taken
-- after gains them with no change here.
--
-- `query_to_xml` is how a set-returning count is taken over a dynamically-named
-- table without plpgsql. Row counts are exact (not reltuples estimates) because
-- the whole point is to assert equality after a restore; that means a scan per
-- table, which is cheap at this database's size and would need revisiting only
-- if `tokens` grew by orders of magnitude.
select
	jsonb_pretty (
		jsonb_build_object(
			'server_version',
			current_setting('server_version'),
			'database',
			current_database(),
			-- Exact row count for every base table in `public`.
			'row_counts',
			(
				select
					coalesce(jsonb_object_agg(name, n), '{}'::jsonb)
				from
					(
						select
							c.relname::text as name,
							(
								xpath(
									'/row/c/text()',
									query_to_xml (
										format('select count(*) as c from public.%I', c.relname),
										false,
										true,
										''
									)
								)
							)[1]::text::bigint as n
						from
							pg_class c
							join pg_namespace ns on ns.oid=c.relnamespace
						where
							ns.nspname='public'
							and c.relkind='r'
					) s
			),
			-- Counted separately because a public-only dump is NOT restorable:
			-- scholars.id references auth.users(id) on delete cascade, so a restore
			-- that loses auth orphans every scholar. If this number and the scholar
			-- count disagree after a restore, the auth dump did not land.
			'auth_user_count',
			(
				select
					case
						when to_regclass ('auth.users') is null then null
						else (
							xpath(
								'/row/c/text()',
								query_to_xml ('select count(*) as c from auth.users', false, true, '')
							)
						)[1]::text::bigint
					end
			),
			-- High-water marks on the append-only logs. These are what let a restore
			-- say "replay everything after seq N" precisely, where wall-clock cannot
			-- when a deploy and user activity interleave.
			'watermarks',
			(
				select
					coalesce(jsonb_object_agg(tbl, n), '{}'::jsonb)
				from
					(
						select
							v.tbl,
							(
								xpath(
									'/row/c/text()',
									query_to_xml (
										format('select max(%I) as c from public.%I', v.col, v.tbl),
										false,
										true,
										''
									)
								)
							)[1]::text::bigint as n
						from
							(
								values
									('transactions', 'seq'),
									('token_events', 'seq'),
									('audit_log', 'seq')
							) v (tbl, col)
						where
							exists (
								select
									1
								from
									information_schema.columns
								where
									table_schema='public'
									and table_name=v.tbl
									and column_name=v.col
							)
					) s
			),
			-- The applied migration list pins the schema this data belongs to. A
			-- restore into a tree at a different migration state is a mismatch worth
			-- catching before it corrupts anything.
			'migrations',
			(
				select
					case
						when to_regclass ('supabase_migrations.schema_migrations') is null then '[]'::jsonb
						else coalesce(
							(
								select
									jsonb_agg(
										version
										order by
											version
									)
								from
									supabase_migrations.schema_migrations
							),
							'[]'::jsonb
						)
					end
			),
			-- Extensions are cluster state, not schema state, and a fresh project does
			-- not have pg_net/pg_cron/vault enabled by default.
			'extensions',
			(
				select
					coalesce(jsonb_object_agg(extname, extversion), '{}'::jsonb)
				from
					pg_extension
			),
			-- The realtime publication is dropped during a restore to avoid fanning
			-- every restored row at every connected client. This is the list the
			-- re-arm step must rebuild, captured so it cannot silently shrink.
			'realtime_tables',
			(
				select
					coalesce(
						jsonb_agg(
							format('%s.%s', schemaname, tablename)
							order by
								schemaname,
								tablename
						),
						'[]'::jsonb
					)
				from
					pg_publication_tables
				where
					pubname='supabase_realtime'
			),
			-- A blunt but effective check that RLS survived the round trip: policies
			-- are carried by the schema dump, and a count mismatch means it did not.
			'rls_policy_count',
			(
				select
					count(*)
				from
					pg_policies
				where
					schemaname='public'
			),
			-- Names only. Vault *values* are never captured: they are set by hand on
			-- hosted projects and belong in a password manager, not in a backup that
			-- CI can write. Recording the names is what tells a restore which secrets
			-- must be re-entered before the project is functional.
			'vault_secret_names',
			(
				select
					case
						when to_regclass ('vault.secrets') is null then '[]'::jsonb
						else coalesce(
							(
								select
									jsonb_agg(
										name
										order by
											name
									)
								from
									vault.secrets
							),
							'[]'::jsonb
						)
					end
			)
		)
	);
