-- Pin pg_net to the `extensions` schema so a restore cannot destroy email.
--
-- 20260720020000 created it with `create extension if not exists pg_net;` — no
-- schema override — which puts the extension wherever the search path points. On
-- the local stack Supabase has already installed it into `extensions`, so the
-- statement was a no-op and nobody noticed. On a hosted project created from
-- these migrations it landed in `public`.
--
-- That is a landmine under every restore. A recovery routinely begins with
-- `drop schema public cascade`, and during a real rehearsal against production it
-- did exactly what you would expect: pg_net went with the schema, and nothing
-- brought it back, because extensions are cluster state and pg_dump emits nothing
-- for them under --schema=public.
--
-- The failure that produces is quiet and specific. public.send_email() calls
-- net.http_post; since 20260720010000 made delivery best effort, a missing
-- net.http_post is caught and logged as a warning. The row lands in public.emails,
-- the caller succeeds, the UI reports success — and not one message is ever sent.
-- That is the same silence 20260720020000 was written to end, arrived at from the
-- other direction.
--
-- pg_net is NOT relocatable (pg_extension.extrelocatable = false), so
-- `alter extension ... set schema` is not available; the only way to move it is to
-- drop and recreate. That is safe here: the extension holds no durable user data
-- (net._http_response is a transient delivery log), and plpgsql function bodies
-- are not parsed for dependencies, so `cascade` does not take send_email() with it
-- — verified before writing this.
--
-- Idempotent, and a no-op on any project already correct, including local dev and
-- CI where Supabase installs pg_net into `extensions` for us.
create schema if not exists extensions;

do $$
declare
	_schema text;
begin
	select n.nspname into _schema
	from pg_extension e
	join pg_namespace n on n.oid = e.extnamespace
	where e.extname = 'pg_net';

	if _schema is null then
		-- Fresh project: create it in the right place from the start.
		create extension pg_net with schema extensions;
		raise notice 'pg_net created in schema extensions';
	elsif _schema <> 'extensions' then
		-- Already installed somewhere a restore could delete it.
		raise notice 'pg_net is in schema %, moving it to extensions', _schema;
		drop extension pg_net cascade;
		create extension pg_net with schema extensions;
	else
		raise notice 'pg_net already in schema extensions, nothing to do';
	end if;
end;
$$;

-- Prove the thing that actually matters: that the function send_email() reaches
-- for still resolves. `net` is pg_net's own schema and is created by the extension
-- regardless of where the extension itself lives, so this holds either way — but
-- after a drop-and-recreate it is worth asserting rather than assuming.
do $$
begin
	if to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)') is null
		and not exists (
			select 1 from pg_proc p
			join pg_namespace n on n.oid = p.pronamespace
			where n.nspname = 'net' and p.proname = 'http_post'
		) then
		raise exception 'net.http_post is missing after pinning pg_net; email would silently stop';
	end if;
end;
$$;
