<script lang="ts">
	import { page } from '$app/stores';

	export let to: string;

	$: inactive = $page.url.pathname === to;
</script>

<a href={inactive ? null : to} target={to.startsWith('http') ? '_blank' : null} class:inactive
	><slot />{#if to.startsWith('http')}<sub>🔗</sub>{/if}</a
>

<style>
	a {
		color: var(--salient-color);
		font-weight: 600;
		text-decoration: none;
	}

	a:hover:not(.inactive) {
		text-decoration: underline;
		text-decoration-thickness: 4px;
	}

	a:focus {
		outline: var(--focus-color) solid 4px;
		border-radius: var(--roundedness);
	}

	.inactive {
		color: var(--text-color);
	}
</style>
