<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { PUBLIC_SUPABASE_URL } from '$env/static/public';
	import { SEED_PASSWORD } from '$lib/auth/devPassword';
	import Button from '$lib/components/Button.svelte';
	import Card from '$lib/components/Card.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import { EmptyLabel, ScholarLabel } from '$lib/components/Labels';
	import Note from '$lib/components/Note.svelte';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Row from '$lib/components/Row.svelte';
	import Table from '$lib/components/Table.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { generateORCID } from '$lib/data/ORCID';
	import type { DevScholar } from '$lib/data/SupabaseCRUD.svelte';
	import type LocaleText from '$lib/locales/Locale';
	import { getLocaleContext } from '$routes/Contexts';
	import { getAuth } from '../../Auth.svelte';

	let auth = getAuth();
	const db = getDB();
	const locale = getLocaleContext();

	let error = $state<undefined | ((l: LocaleText) => string)>(undefined);

	// The ORCID callback bounces back here with ?error=orcid when the PKCE code exchange
	// fails (see src/routes/auth/callback/+server.ts). Without this the scholar lands on a
	// login page that looks like nothing happened. $derived rather than a one-time read so
	// it still resolves after a client-side navigation.
	let callbackError = $derived(
		page.url.searchParams.get('error') === 'orcid'
			? (l: LocaleText) => l.page.login.feedback.orcidError
			: undefined
	);

	// An error raised by an action on this page takes precedence over one carried in the
	// URL, so a fresh failure replaces the stale query-param message.
	let shownError = $derived(error ?? callbackError);

	// The dev-only controls (mock ORCID sign-in + seeded-user password grant) let us
	// exercise auth locally, where the real ORCID custom-OIDC provider cannot be
	// configured. Gated on the Supabase URL being local rather than on PUBLIC_ENV !==
	// 'prod': staging is a non-prod environment pointed at a hosted project, and it must
	// exercise the real ORCID path — otherwise the one environment that can validate
	// custom OIDC before production would be testing a mock instead, and would accumulate
	// throwaway @orcid.example auth users. Mirrors the same check in VerifyEmail.svelte.
	const devLogin =
		PUBLIC_SUPABASE_URL.includes('127.0.0.1') || PUBLIC_SUPABASE_URL.includes('localhost');
	let mockOrcidId = $state('');
	let mockOrcidName = $state('');
	let email = $state('');
	let password = $state('');

	/** The seeded scholars, offered as one-click sign-ins. Testing a flow as a
	 * particular scholar otherwise meant opening seed.sql to find their address
	 * and recalling the shared password. Local stacks only — the same gate as
	 * the password form itself, so this never renders against staging or
	 * production, where these accounts don't exist and the password wouldn't
	 * work if they did. */
	let devScholars = $state<DevScholar[]>([]);
	let devLabels = $state<Map<string, string[]>>(new Map());

	$effect(() => {
		if (!devLogin) return;
		(async () => {
			const [{ data: scholars }, { data: venues }, { data: currencies }] = await Promise.all([
				db().getScholarsForDevSignIn(),
				db().getVenues(),
				db().getCurrencies()
			]);
			devScholars = scholars ?? [];
			// Label the accounts by what they can do, since that's what decides
			// which one you want to be for the flow you're testing.
			const labels = new Map<string, string[]>();
			const add = (id: string, label: string) => labels.set(id, [...(labels.get(id) ?? []), label]);
			for (const scholar of devScholars) if (scholar.steward) add(scholar.id, 'steward');
			for (const venue of venues ?? [])
				for (const admin of venue.admins) add(admin, `admin of ${venue.title}`);
			for (const currency of currencies ?? [])
				for (const minter of currency.minters) add(minter, `minter of ${currency.name}`);
			devLabels = labels;
		})();
	});

	/** Sign in as a seeded scholar using the password every seeded user shares
	 * (supabase/seed.sql sets it for all of them).
	 *
	 * Note this signs in with `scholars.email`, which is a *contact* address,
	 * not the auth identity — identity is ORCID (see ARCHITECTURE). The seed
	 * sets both to the same value, so this works for seeded accounts; if one has
	 * since verified a different contact address, the grant fails and the error
	 * below says so. The address is shown next to each name for exactly that
	 * reason. The auth email is deliberately not readable from the browser, so
	 * there is nothing better to key on here without exposing it. */
	async function signInAs(scholar: DevScholar) {
		if (scholar.email === null) return;
		const response = await auth().signInWithPassword(scholar.email, SEED_PASSWORD);
		if (typeof response === 'string') {
			error = undefined;
			goto(`/scholar/${response}`);
		} else {
			console.error(response);
			error = (l) => l.page.login.feedback.signInError;
		}
	}

	// When the user is authenticated, redirect to their home page.
	$effect(() => {
		if (auth().isAuthenticated()) {
			goto(`/scholar/${auth().getUserID()}`);
		}
	});

	/** Real ORCID sign-in (production): redirect to the custom-OIDC provider. */
	async function signInWithORCID() {
		const authError = await auth().signInWithORCID(`${page.url.origin}/auth/callback`);
		if (authError) {
			console.error(authError);
			error = (l) => l.page.login.feedback.orcidError;
		} else {
			error = undefined;
		}
	}

	/** Local dev-only mock: create (or re-enter) a scholar to see the onboarding flow.
	 * A blank iD mints a fresh scholar (new-account onboarding); a reused iD returns to
	 * that account. */
	async function signInWithMockORCID() {
		const id = mockOrcidId.trim() || generateORCID();
		const name = mockOrcidName.trim() || 'Test Scholar';
		const response = await auth().signInWithMockORCID(id, name);
		if (typeof response === 'string') {
			error = undefined;
			goto(`/scholar/${response}`);
		} else {
			console.error(response);
			error = (l) => l.page.login.feedback.mockOrcidError;
		}
	}
</script>

<Page icon={ScholarLabel} title={(l) => l.page.login.title} breadcrumbs={[]}>
	{#if auth().isAuthenticated()}
		<Paragraph text={(l) => l.page.login.paragraph.loggedIn} />
	{:else if !devLogin}
		<!-- The real thing: ORCID is the only way in outside local development. -->
		<Form>
			<Button
				strings={(l) => l.page.login.button.orcid}
				testid="orcid-signin"
				type="submit"
				action={signInWithORCID}
			/>
		</Form>
		<Note path={(l) => l.page.login.note.orcid} />
	{:else}
		<!-- Local development. One warning for the whole page, then the thing you
		     almost always want (sign in as a seeded scholar), then the two
		     fallbacks it can't cover. -->
		<Feedback warning text={(l) => l.page.login.feedback.seededDev} testid="seeded-dev" />

		{#if devScholars.length > 0}
			<Table>
				{#snippet header()}
					<th>{locale().page.login.table.scholar}</th>
					<th>{locale().page.login.table.email}</th>
					<th>{locale().page.login.table.roles}</th>
				{/snippet}
				{#each devScholars as scholar, index}
					{@const address = scholar.email}
					{#if address !== null}
						{@const label = scholar.name ?? address}
						{@const roles = devLabels.get(scholar.id) ?? []}
						<tr data-testid="seeded-{index}">
							<td>
								<Button
									testid="seeded-signin-{index}"
									strings={(l) => ({ ...l.page.login.button.signInAs, label })}
									action={() => signInAs(scholar)}>{label}</Button
								>
							</td>
							<td>{address}</td>
							<td>
								<Row>
									{#each roles as role}<Tag>{role}</Tag>{:else}{EmptyLabel}{/each}
								</Row>
							</td>
						</tr>
					{/if}
				{/each}
			</Table>
		{/if}

		<!-- Kept, and kept visible, for the accounts the table can't offer: one
		     created below (no contact email, so it never appears there), or one
		     whose contact address has diverged from its auth identity. It is also
		     what the Playwright helper drives, and its hydration barrier. -->
		<Feedback text={(l) => l.page.login.feedback.passwordDev} testid="password-dev" />
		<Form>
			<TextField
				strings={(l) => l.page.login.field.email}
				name="email"
				size={19}
				bind:text={email}
				testid="email-input"
			/>
			<TextField
				strings={(l) => l.page.login.field.password}
				name="password"
				size={19}
				bind:text={password}
				testid="password-input"
			/>
			<Button
				strings={(l) => l.page.login.button.signIn}
				testid="password-submit"
				type="submit"
				action={async () => {
					const response = await auth().signInWithPassword(email, password);
					if (typeof response === 'string') {
						error = undefined;
						goto(`/scholar/${response}`);
					} else {
						console.error(response);
						error = (l) => l.page.login.feedback.signInError;
					}
				}}
				active={email.length > 0 && password.length > 0}
			/>
		</Form>

		<!-- Not a sign-in at all: this mints a brand-new scholar, which is the
		     only way to see the first-run experience (no contact email, the
		     verification banner) that signing in as a seeded scholar can't reach. -->
		<Cards>
			<Card
				icon={ScholarLabel}
				subheader
				strings={(l) => l.page.login.card.newScholar}
				testid="mock-orcid-card"
			>
				<Form>
					<TextField
						strings={(l) => l.page.login.field.orcidId}
						name="mock-orcid-id"
						size={19}
						bind:text={mockOrcidId}
						testid="mock-orcid-id"
					/>
					<TextField
						strings={(l) => l.page.login.field.name}
						name="mock-orcid-name"
						size={19}
						bind:text={mockOrcidName}
						testid="mock-orcid-name"
					/>
					<Button
						strings={(l) => l.page.login.button.mockOrcid}
						testid="orcid-signin"
						type="submit"
						action={signInWithMockORCID}
					/>
				</Form>
			</Card>
		</Cards>
	{/if}

	{#if shownError}
		<Feedback error text={shownError} testid="login-error" />
	{/if}
</Page>
