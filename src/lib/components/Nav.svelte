<script lang="ts">
	import { goto } from '$app/navigation';
	import Text from '$lib/locales/Text.svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import { getAuth } from '../../routes/Auth.svelte';
	import { getPendingActions } from '../../routes/feedback.svelte';
	import Button from './Button.svelte';
	import Dots from './Dots.svelte';
	import { ScholarLabel, SubmissionLabel, VenueLabel } from './Labels';
	import Link from './Link.svelte';

	const locale = getLocaleContext();

	const routes = [
		{ path: '/', label: locale().header.home },
		{ path: '/venues', label: locale().header.venues }
	];

	let auth = getAuth();

	let pending = $derived(getPendingActions());

	const { breadcrumbs }: { breadcrumbs: [string, string][] } = $props();
</script>

<header>
	{#each routes as route}
		<div class="link">
			<Link size="small" to={route.path}>{route.label}</Link>
		</div>
	{/each}
	{#each breadcrumbs as [url, label]}
		<small>&gt;</small>
		<div class="link">
			<Link
				size="small"
				to={url}
				icon={url.startsWith('/venue')
					? VenueLabel
					: url.startsWith('/scholar')
						? ScholarLabel
						: url.startsWith('/submission')
							? SubmissionLabel
							: null}>{label}</Link
			>
		</div>
	{/each}
	<div class="authenticated">
		<div class="feedback">
			{#if pending > 0}
				{#if pending > 1}{pending}{/if}
				<Dots></Dots>
			{:else}✔ {locale().header.saved}{/if}
		</div>
		{#if auth().isAuthenticated()}
			<div class="link">
				<Link size="small" to="/scholar/{auth().getUserID()}">{auth().user?.email}</Link>
			</div>
			<div class="link">
				<Button
					small
					testid="logout-button"
					strings={(l) => l.component.header.logout}
					action={() => {
						auth().signOut();
						goto('/login');
					}}
				/>
			</div>
		{:else}
			<div class="link">
				<Link size="small" to="/login"><Text path={(l) => l.header.link.login} /></Link>
			</div>
		{/if}
	</div>
</header>

<style>
	header {
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		gap: calc(var(--spacing) / 2);
		row-gap: var(--spacing);
		align-items: center;
		border-block-end: var(--border-color) solid var(--border-width);
		background: var(--background-color);
		padding: calc(var(--spacing) / 2) var(--spacing);

		/* The header is sticky */
		position: sticky;
		top: 0;
		z-index: 2;
	}

	.link {
		display: inline-block;
	}

	.feedback {
		font-size: var(--extra-small-font-size);
		background: var(--salient-color-faded);
		border-radius: var(--roundedness);
		padding: var(--roundedness);
	}

	.authenticated {
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		gap: var(--spacing);
		margin-inline-start: auto;
		align-items: center;
	}
</style>
