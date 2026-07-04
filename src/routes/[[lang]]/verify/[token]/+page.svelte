<script lang="ts">
	import { invalidate } from '$app/navigation';
	import Feedback from '$lib/components/Feedback.svelte';
	import { ScholarLabel } from '$lib/components/Labels';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
	import Text from '$lib/locales/Text.svelte';
	import { getAuth } from '../../../Auth.svelte';

	let { data } = $props();

	let auth = getAuth();

	// On success, refresh the layout so scholars.email reloads and the unverified-email
	// banner clears. The server load already consumed the token, so this invalidate does
	// not re-run it (that load has no 'supabase:auth' dependency).
	$effect(() => {
		if (data.status === 'verified' && auth().isAuthenticated()) {
			invalidate('supabase:auth');
		}
	});
</script>

<Page icon={ScholarLabel} title={(l) => l.page.verify.title} breadcrumbs={[]}>
	{#if data.status === 'verified'}
		<Feedback testid="verify-verified" text={(l) => l.page.verify.verified} />
	{:else if data.status === 'expired'}
		<Feedback error testid="verify-expired" text={(l) => l.page.verify.expired} />
	{:else if data.status === 'error'}
		<Feedback error testid="verify-error" text={(l) => l.page.verify.error} />
	{:else}
		<Feedback error testid="verify-invalid" text={(l) => l.page.verify.invalid} />
	{/if}

	{#if auth().isAuthenticated()}
		<Link to="/scholar/{auth().getUserID()}">
			<Text path={(l) => l.page.verify.profile} />
		</Link>
	{:else}
		<Link to="/login">
			<Text path={(l) => l.page.verify.login} />
		</Link>
	{/if}
</Page>
