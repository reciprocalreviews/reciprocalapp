<script lang="ts">
	import Link from './Link.svelte';
	import Button from './Button.svelte';
	import { getAuth } from '../../routes/Auth.svelte';
	import { goto } from '$app/navigation';

	const routes = [
		{ path: '/', label: 'Home' },
		{ path: '/venues', label: 'Venues' },
		{ path: '/about', label: 'About' }
	];

	let auth = getAuth();
</script>

<header>
	{#each routes as route}<div class="link"><Link to={route.path}>{route.label}</Link></div>{/each}
	<div class="authenticated">
		{#if auth.isAuthenticated()}
			<div class="link">
				<Link small to="https://github.com/reciprocalreviews/reciprocalapp/issues/">Feedback</Link>
			</div>
			<div class="link"><Link small to="/scholar/{auth.getUserID()}">{auth.user?.email}</Link></div>
			<div class="link">
				<Button
					tip="Sign out"
					action={() => {
						auth.signOut();
						goto('/login');
					}}>Logout</Button
				>
			</div>
		{:else}
			<div class="link"><Link to="/login">Login</Link></div>
		{/if}
	</div>
</header>

<style>
	header {
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		gap: calc(2 * var(--spacing));
		row-gap: var(--spacing);
		align-items: center;
		padding-bottom: var(--spacing);
		border-block-end: var(--border-color) solid var(--border-width);
	}

	.link {
		display: inline-block;
	}

	.authenticated {
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		gap: calc(2 * var(--spacing));
		margin-inline-start: auto;
		align-items: center;
	}
</style>
