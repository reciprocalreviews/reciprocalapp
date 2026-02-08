<script lang="ts">
	import Link from './Link.svelte';
	import Button from './Button.svelte';
	import { getAuth } from '../../routes/Auth.svelte';
	import { goto } from '$app/navigation';
	import { getPendingActions } from '../../routes/feedback.svelte';
	import Dots from './Dots.svelte';

	const routes = [
		{ path: '/', label: 'Home' },
		{ path: '/venues', label: 'Venues' }
	];

	let auth = getAuth();

	let pending = $derived(getPendingActions());
</script>

<header>
	{#each routes as route}<div class="link">
			<Link small to={route.path}>{route.label}</Link>
		</div>{/each}
	<div class="authenticated">
		<div
			class="feedback"
			title={pending === 0
				? 'No pending saves'
				: `${pending} pending saves${pending > 1 ? 's' : ''}`}
		>
			{#if pending > 0}
				{#if pending > 1}{pending}{/if}
				<Dots></Dots>
			{:else}✔ saved{/if}
		</div>
		{#if auth.isAuthenticated()}
			<div class="link">
				<Link small to="/scholar/{auth.getUserID()}">{auth.user?.email}</Link>
			</div>
			<div class="link">
				<Button
					small
					tip="Sign out"
					action={() => {
						auth.signOut();
						goto('/login');
					}}>Logout</Button
				>
			</div>
		{:else}
			<div class="link"><Link small to="/login">Login</Link></div>
		{/if}
	</div>
</header>

<style>
	header {
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		gap: var(--spacing);
		row-gap: var(--spacing);
		align-items: center;
		border-block-end: var(--border-color) solid var(--border-width);
		background: var(--background-color);
		padding: var(--spacing);

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
