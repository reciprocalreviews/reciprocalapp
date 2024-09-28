<script lang="ts">
	import { page } from '$app/stores';

	export let to: string;

	$: inactive = $page.url.pathname === to;
</script>

<a
	href={inactive ? null : to}
	target={to.startsWith('http') ? '_blank' : null}
	aria-current={inactive ? 'page' : null}
	><slot />{#if to.startsWith('http')}<sub>⏵</sub>{/if}</a
>

<style>
	a {
		color: var(--salient-color);
		font-weight: 600;
		text-decoration: none;
	}

	a:hover:not([aria-current]) {
		text-decoration: underline;
		text-decoration-thickness: var(--thick-border);
	}

	a:focus {
		outline: var(--focus-color) solid var(--thick-border);
		border-radius: var(--roundedness);
	}

	a[aria-current] {
		color: var(--text-color);
	}
</style>
