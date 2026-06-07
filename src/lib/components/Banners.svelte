<script lang="ts">
	import { updated } from '$app/state';
	import { PUBLIC_ENV } from '$env/static/public';
	import { BETA } from '$lib/constants';
	import Text from '$lib/locales/Text.svelte';
	import { getFeedback, removeError } from '$routes/feedback.svelte';
	import Banner from './Banner.svelte';
	import Link from './Link.svelte';

	let feedback = $derived(getFeedback());

	/** Locally hide the update banner once the scholar dismisses it. */
	let updateDismissed = $state(false);
</script>

<div class="banners">
	{#if BETA}
		<Banner level="beta" testid="banner-beta">
			<Text markdown path={(l) => l.banner.beta.lead} />
		</Banner>
	{/if}

	{#if updated.current && !updateDismissed}
		<Banner
			level="update"
			testid="banner-update"
			action={{ strings: (l) => l.banner.update.refresh, do: () => location.reload() }}
			dismiss={() => (updateDismissed = true)}
		>
			<Text path={(l) => l.banner.update.message} />
			<Link to="/updates"><Text path={(l) => l.banner.update.updates} /></Link>
		</Banner>
	{/if}

	{#if PUBLIC_ENV === 'test'}
		<Banner level="warning" testid="banner-test">
			<Text path={(l) => l.header.feedback.testWarning} />
		</Banner>
	{/if}

	<section aria-live="assertive">
		{#each feedback as item, index (index)}
			<Banner
				level={item.level}
				detail={item.error?.message}
				dismiss={() => removeError(index)}
				testid="feedback-{item.level}"
			>
				{item.message}
			</Banner>
		{/each}
	</section>
</div>

<style>
	.banners {
		display: flex;
		flex-direction: column;
		gap: 0;
	}

	section {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
	}
</style>
