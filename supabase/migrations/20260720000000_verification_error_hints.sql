-- Tag request_email_verification's failures with machine-readable hints.
--
-- The RPC already distinguishes four failure modes, but every one of them reached the
-- interface as the same sentence: "Unable to send a verification email." That is actively
-- misleading — a scholar told to wait a moment is given no reason to try again, and an
-- environment missing its `site_url` vault secret looks identical to a transient fault.
-- This was found while verifying staging, where a missing secret produced a dead end with
-- nothing to act on.
--
-- Each raise now carries `hint`, which PostgREST returns in the error body and supabase-js
-- exposes as `error.hint`. The interface maps the hint to a specific message and falls back
-- to the generic one for anything unrecognized. Hints rather than message matching, so the
-- wording stays free to change (and to be localized) without breaking the mapping, and
-- rather than custom SQLSTATEs, which PostgREST does not pass through as faithfully.

create or replace function public.request_email_verification (_email text) returns void language "plpgsql" security definer
set
	"search_path" to 'public', 'pg_temp' as $$
declare
	_caller uuid := (select auth.uid());
	_token text;
	_origin text := private.get_secret('site_url');
	_previous timestamptz;
begin
	if _caller is null then
		raise exception 'Authentication required' using hint = 'auth_required';
	end if;
	if _email is null or _email !~ '^.+@.+\..+$' then
		raise exception 'A valid email address is required' using hint = 'invalid_email';
	end if;
	-- A deployment that has not had its `site_url` vault secret set cannot build a
	-- verification link. Say so, rather than letting it look like a delivery failure.
	if _origin is null or _origin = '' then
		raise exception 'The site_url vault secret is not configured' using hint = 'not_configured';
	end if;

	-- Rate limit. Each call emails an address the caller chose, so without a cooldown this
	-- RPC is a mail amplifier. One per minute is well below any legitimate resend cadence.
	select created_at into _previous from public.email_verifications where scholar = _caller;
	if _previous is not null and _previous > now() - interval '1 minute' then
		raise exception 'Please wait a moment before requesting another verification email' using hint = 'cooldown';
	end if;

	_token := encode(extensions.gen_random_bytes(32), 'hex');

	insert into public.email_verifications (scholar, token_hash, candidate_email, created_at, expires_at)
	values (
		_caller,
		encode(extensions.digest(_token, 'sha256'), 'hex'),
		lower(btrim(_email)),
		now(),
		now() + interval '15 minutes'
	)
	on conflict (scholar) do update
		set token_hash = excluded.token_hash,
			candidate_email = excluded.candidate_email,
			created_at = excluded.created_at,
			expires_at = excluded.expires_at;

	-- scholar AND sender are deliberately null: the emails SELECT policy grants reads to
	-- both the recipient and the sender, so attributing this row to the requester would let
	-- them read the token back out of the args — the very leak this design closes. With
	-- both null no policy branch matches and the row is unreadable by anyone.
	insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
	values (
		'VerifyEmail',
		null,
		null,
		null,
		lower(btrim(_email)),
		null,
		null,
		jsonb_build_array(rtrim(_origin, '/') || '/verify/' || _token)
	);
end;
$$;

alter function public.request_email_verification (text) OWNER to "postgres";

revoke execute on function public.request_email_verification (text)
from
	public,
	anon;

grant execute on function public.request_email_verification (text) to authenticated;
