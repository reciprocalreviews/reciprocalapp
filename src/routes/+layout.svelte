<!-- This Source Code Form is subject to the terms of the Mozilla Public
  -- License, v. 2.0. If a copy of the MPL was not distributed with this
  -- file, You can obtain one at http://mozilla.org/MPL/2.0/. 
  -->

<script>
	import { dev } from '$app/environment';
	import { goto } from '$app/navigation';
	import Header from '$lib/components/Header.svelte';
	import { Auth, AuthSymbol, DatabaseSymbol } from '$lib/Context';
	import MockDatabase from '$lib/data/MockDatabase';
	import { onMount, setContext } from 'svelte';

	/** Always go home in production, pre-release */
	onMount(() => {
		if (!dev) goto('/');
	});

	/** Set a database connection context for all to use. */
	setContext(DatabaseSymbol, new MockDatabase());

	/** Set an auth connection context for all to use */
	setContext(AuthSymbol, Auth);
</script>

{#if dev}
	<Header />
{/if}
<slot />
