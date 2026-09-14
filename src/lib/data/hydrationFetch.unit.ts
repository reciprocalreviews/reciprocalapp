import { expect, test } from 'vitest';
import { CLIENT_INFO, withStableClientInfo } from './hydrationFetch';

/** A fetch that records what it was asked for and answers nothing. */
function recorder() {
	const calls: { input: RequestInfo | URL; init?: RequestInit }[] = [];
	const fetcher = ((input: RequestInfo | URL, init?: RequestInit) => {
		calls.push({ input, init });
		return Promise.resolve(new Response(null));
	}) as typeof fetch;
	return { calls, fetcher };
}

function sentHeaders(init: RequestInit | undefined): Record<string, string> {
	return Object.fromEntries(new Headers(init?.headers));
}

test('pins X-Client-Info whether the headers arrive as a Headers instance, an object, or not at all', () => {
	const { calls, fetcher } = recorder();
	const stable = withStableClientInfo(fetcher);

	stable('https://example.test/a', {
		headers: new Headers({ 'X-Client-Info': 'supabase-ssr/0.12.7 createBrowserClient' })
	});
	stable('https://example.test/b', {
		headers: { 'x-client-info': 'supabase-ssr/0.12.7 createServerClient' }
	});
	stable('https://example.test/c');

	for (const call of calls) expect(sentHeaders(call.init)['x-client-info']).toBe(CLIENT_INFO);
});

test('the server and browser sides now hash alike', () => {
	// The same hash SvelteKit computes on each side: the request's headers, joined.
	const key = (init: RequestInit | undefined) => [...new Headers(init?.headers)].join(',');
	const { calls, fetcher } = recorder();
	const stable = withStableClientInfo(fetcher);

	const common = { apikey: 'key', Authorization: 'Bearer token', Accept: 'application/json' };
	stable('https://example.test/rest/v1/scholars', {
		headers: { ...common, 'X-Client-Info': 'supabase-ssr/0.12.7 createServerClient' }
	});
	stable('https://example.test/rest/v1/scholars', {
		headers: { ...common, 'X-Client-Info': 'supabase-ssr/0.12.7 createBrowserClient' }
	});

	expect(key(calls[0].init)).toBe(key(calls[1].init));
});

test('everything else passes through untouched', () => {
	const { calls, fetcher } = recorder();
	const stable = withStableClientInfo(fetcher);

	stable('https://example.test/rest/v1/rpc/x', {
		method: 'POST',
		body: '{"a":1}',
		headers: { apikey: 'key', 'Content-Type': 'application/json' }
	});

	const { input, init } = calls[0];
	expect(input).toBe('https://example.test/rest/v1/rpc/x');
	expect(init?.method).toBe('POST');
	expect(init?.body).toBe('{"a":1}');
	const headers = sentHeaders(init);
	expect(headers['apikey']).toBe('key');
	expect(headers['content-type']).toBe('application/json');
});

test('a Request object keeps its own headers', () => {
	const { calls, fetcher } = recorder();
	const stable = withStableClientInfo(fetcher);

	stable(new Request('https://example.test/a', { headers: { apikey: 'key' } }));

	const headers = sentHeaders(calls[0].init);
	expect(headers['apikey']).toBe('key');
	expect(headers['x-client-info']).toBe(CLIENT_INFO);
});
