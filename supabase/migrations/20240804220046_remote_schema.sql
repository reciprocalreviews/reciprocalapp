set
	statement_timeout=0;

set
	lock_timeout=0;

set
	idle_in_transaction_session_timeout=0;

set
	client_encoding='UTF8';

set
	standard_conforming_strings=on;

select
	pg_catalog.set_config ('search_path', '', false);

set
	check_function_bodies=false;

set
	xmloption=content;

set
	client_min_messages=warning;

set
	row_security=off;

comment on SCHEMA "public" is 'standard public schema';

create extension IF not exists "pg_graphql"
with
	SCHEMA "graphql";

create extension IF not exists "pg_stat_statements"
with
	SCHEMA "extensions";

create extension IF not exists "pgcrypto"
with
	SCHEMA "extensions";

create extension IF not exists "pgjwt"
with
	SCHEMA "extensions";

create extension IF not exists "supabase_vault"
with
	SCHEMA "vault";

create extension IF not exists "uuid-ossp"
with
	SCHEMA "extensions";

alter publication "supabase_realtime" OWNER to "postgres";

grant USAGE on SCHEMA "public" to "postgres";

grant USAGE on SCHEMA "public" to "anon";

grant USAGE on SCHEMA "public" to "authenticated";

grant USAGE on SCHEMA "public" to "service_role";

alter default privileges for ROLE "postgres" in SCHEMA "public"
grant all on SEQUENCES to "postgres";

alter default privileges for ROLE "postgres" in SCHEMA "public"
grant all on SEQUENCES to "anon";

alter default privileges for ROLE "postgres" in SCHEMA "public"
grant all on SEQUENCES to "authenticated";

alter default privileges for ROLE "postgres" in SCHEMA "public"
grant all on SEQUENCES to "service_role";

alter default privileges for ROLE "postgres" in SCHEMA "public"
grant all on FUNCTIONS to "postgres";

alter default privileges for ROLE "postgres" in SCHEMA "public"
grant all on FUNCTIONS to "anon";

alter default privileges for ROLE "postgres" in SCHEMA "public"
grant all on FUNCTIONS to "authenticated";

alter default privileges for ROLE "postgres" in SCHEMA "public"
grant all on FUNCTIONS to "service_role";

alter default privileges for ROLE "postgres" in SCHEMA "public"
grant all on TABLES to "postgres";

alter default privileges for ROLE "postgres" in SCHEMA "public"
grant all on TABLES to "anon";

alter default privileges for ROLE "postgres" in SCHEMA "public"
grant all on TABLES to "authenticated";

alter default privileges for ROLE "postgres" in SCHEMA "public"
grant all on TABLES to "service_role";

reset all;
