<script lang="ts">
	import Link from './Link.svelte';
	import { getAuth } from '$lib/Context';
	import Button from './Button.svelte';

	const routes = [
		{ path: '/', label: 'Home' },
		{ path: '/sources', label: 'Sources' },
		{ path: '/about', label: 'About' }
	];

	const auth = getAuth();
</script>

<div class="header">
	{#each routes as route}<div class="link"><Link to={route.path}>{route.label}</Link></div>{/each}
	<div class="authenticated">
		{#if $auth}
			<div class="link"><Link to="/scholar/{$auth.getScholarID()}">Profile</Link></div>
			<div class="link"><Button action={() => $auth?.logout()}>Logout</Button></div>
		{:else}
			<div class="link"><Link to="/login">Login</Link></div>
		{/if}
	</div>
</div>

<style>
	.header {
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		gap: calc(2 * var(--spacing));
		row-gap: var(--spacing);
		align-items: center;
	}

	.link {
		display: inline-block;
	}

	.authenticated {
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		gap: calc(2 * var(--spacing));
		margin-left: auto;
		align-items: center;
	}
</style>
