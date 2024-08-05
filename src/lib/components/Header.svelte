<script lang="ts">
	import Link from './Link.svelte';
	import Button from './Button.svelte';
	import { getAuth } from '../../routes/+layout.svelte';

	const routes = [
		{ path: '/', label: 'Home' },
		{ path: '/sources', label: 'Sources' },
		{ path: '/about', label: 'About' }
	];

	let auth = getAuth();
</script>

<div class="header">
	{#each routes as route}<div class="link"><Link to={route.path}>{route.label}</Link></div>{/each}
	<div class="authenticated">
		{#if auth.authenticated()}
			<!-- <div class="link"><Link to="/scholar/{$auth.getScholarID()}">Profile</Link></div> -->
			<div class="link"><Button action={() => auth.signOut()}>Logout</Button></div>
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
