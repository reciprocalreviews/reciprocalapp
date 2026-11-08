<script lang="ts">
	import { atCap, type Load } from '#lib/data/load.js';
	import Text from '#lib/locales/Text.svelte';

	/** A scholar's active papers in a role against the cap they set for it, then what
	 * they carry elsewhere, for whoever is deciding whether to give them another. */
	const { load }: { load: Load } = $props();

	const full = $derived(atCap(load));
</script>

<div class="load">
	{#if load.cap === null}
		<div data-testid="papers-load">
			<Text path={(l) => l.view.load.noCap} inputs={{ used: load.used.toString() }} />
		</div>
	{:else}
		<div class:over-cap={full} data-testid="papers-load">
			<Text
				path={(l) =>
					load.cap !== null && load.used > load.cap
						? l.view.load.overCap
						: full
							? l.view.load.atCap
							: l.view.load.underCap}
				inputs={{ used: load.used.toString(), cap: load.cap.toString() }}
			/>
		</div>
	{/if}
	{#if load.otherRoles > 0}
		<div class="more" data-testid="other-roles-load">
			<Text path={(l) => l.view.load.otherRoles} inputs={{ count: load.otherRoles.toString() }} />
		</div>
	{/if}
	{#if load.elsewhere > 0}
		<div class="more" data-testid="elsewhere-load">
			<Text path={(l) => l.view.load.elsewhere} inputs={{ count: load.elsewhere.toString() }} />
		</div>
	{/if}
</div>

<style>
	.over-cap {
		color: var(--error-color);
		font-weight: bold;
	}

	.more {
		font-size: var(--extra-small-font-size);
		color: var(--inactive-color);
	}
</style>
