<script lang="ts">
	import { goto } from '$app/navigation';
	import Banners from '$lib/components/Banners.svelte';
	import Text from '$lib/locales/Text.svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import type PageHeader from '$routes/PageHeader';
	import { getContext, untrack } from 'svelte';
	import { Tween } from 'svelte/motion';
	import { cubicOut } from 'svelte/easing';
	import { getAuth } from '../../routes/Auth.svelte';
	import { getPendingActions } from '../../routes/feedback.svelte';
	import Button from './Button.svelte';
	import Dots from './Dots.svelte';
	import EditableText from './EditableText.svelte';
	import { ScholarLabel, SubmissionLabel, TokenLabel, VenueLabel } from './Labels';
	import Lead from './Lead.svelte';
	import Link from './Link.svelte';
	import Loading from './Loading.svelte';

	const locale = getLocaleContext();

	let auth = getAuth();

	let pending = $derived(getPendingActions());

	const {
		breadcrumbs,
		inProd,
		tokens = 0
	}: { breadcrumbs: [string, string][]; inProd: boolean; tokens?: number } = $props();

	/** Whether the viewer asked for less motion. The CSS guard below can only
	 * stop the flash; the counting is JavaScript, so it has to be checked here
	 * too. `matchMedia` is browser-only — assume no preference during SSR. */
	const reducedMotion =
		typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

	/** The displayed balance, rolled toward the real one so a change is felt
	 * rather than just appearing. `Tween` is Svelte's own motion primitive — no
	 * new dependency — and this is its first use in the codebase. */
	const balance = new Tween(
		untrack(() => tokens),
		{
			duration: reducedMotion ? 0 : 600,
			easing: cubicOut
		}
	);

	/** True briefly after the balance changes, to flash the widget. Separate
	 * from the tween so the highlight can be dropped for reduced motion while
	 * the number itself still updates. */
	let changed = $state(false);
	let flash: ReturnType<typeof setTimeout> | undefined;

	$effect(() => {
		const next = tokens;
		// The tween starts at the balance the page loaded with, so this is only
		// unequal once the balance genuinely moves — which is why arriving on a
		// page doesn't animate, but earning or spending does.
		if (next === balance.target) return;
		balance.set(next);
		changed = true;
		clearTimeout(flash);
		flash = setTimeout(() => (changed = false), 1200);
	});

	$effect(() => () => clearTimeout(flash));

	// In production only /updates and /about are reachable (everything else redirects home),
	// so the header offers just those plus Home; otherwise it shows the full navigation.
	const routes = $derived(
		inProd
			? [
					{ path: '/', label: locale().header.home },
					{ path: '/updates', label: locale().footer.link.updates },
					{ path: '/about', label: locale().footer.link.about }
				]
			: [
					{ path: '/', label: locale().header.home },
					{ path: '/venues', label: locale().header.venues }
				]
	);

	const pageHeader = getContext<PageHeader>('pageHeader');
</script>

<header>
	<div class="nav">
		{#each routes as route}
			<div class="link">
				<Link size="small" to={route.path}>{route.label}</Link>
			</div>
		{/each}
		{#if !inProd}
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
				{#if pending > 0}
					<div class="feedback">
						{#if pending > 1}{pending}{/if}
						<Dots></Dots>
					</div>
				{/if}
				{#if auth().isAuthenticated()}
					<a
						class="balance"
						class:changed
						href="/scholar/{auth().getUserID()}#tokens"
						title={locale().header.balance}
						aria-label={locale().header.balance}
						data-testid="header-balance"
					>
						<span class="star">{TokenLabel}</span>{Math.round(balance.current)}
					</a>
					<div class="link">
						<Link size="small" to="/scholar/{auth().getUserID()}"
							><Text path={(l) => l.header.link.profile} /></Link
						>
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
		{/if}
	</div>
	<Banners />
	{#if pageHeader?.title}
		<div class="page-header">
			<h1 class="page-header-title" class:wobble={pageHeader.wobble} data-testid="page-header">
				<span class="emoji">{pageHeader.icon}</span>
				{#if pageHeader.edit}
					<EditableText
						text={pageHeader.title}
						valid={pageHeader.edit.valid}
						edit={pageHeader.edit.update}
						strings={(l) => ({ placeholder: pageHeader.edit!.placeholder(l) })}
						testid="page-title-edit"
					/>
				{:else if pageHeader.title.length > 0}
					{pageHeader.title}
				{:else}
					<Loading />
				{/if}
			</h1>
			{#if pageHeader.subtitle || pageHeader.details}
				<div class="details">
					{#if pageHeader.subtitle}<Lead>{@render pageHeader.subtitle()}</Lead>{/if}
					{@render pageHeader.details?.()}
				</div>
			{/if}
		</div>
	{/if}
</header>

<style>
	header {
		/* The header is sticky */
		position: sticky;
		top: 0;
		z-index: 2;
		display: flex;
		flex-direction: column;
		gap: 0;
	}

	.nav {
		padding-left: calc(var(--spacing) / 2);
		padding-right: var(--spacing);
		padding-top: calc(var(--spacing) / 2);
		padding-bottom: calc(var(--spacing) / 2);
		display: flex;
		flex-direction: row;
		flex-wrap: wrap;
		gap: calc(var(--spacing) / 2);
		row-gap: var(--spacing);
		align-items: center;
		background: var(--background-color);
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

	.page-header {
		width: 100%;
		display: flex;
		flex-direction: column;
		gap: var(--spacing-half);
		padding-top: 0;
		background: var(--background-color);
		margin-bottom: var(--spacing);
		overflow-x: clip;
	}

	.page-header-title {
		align-items: baseline;
	}

	.emoji {
		font-family: 'Noto Emoji', 'Josefin Sans', sans-serif;
		font-size: 80%;
	}

	h1 {
		display: flex;
		gap: 0.5rem;
		align-items: center;
		margin: 0;
	}

	@keyframes wobble {
		0%,
		100% {
			transform: translateX(0);
		}
		20% {
			transform: translateX(-5px);
		}
		40% {
			transform: translateX(5px);
		}
		60% {
			transform: translateX(-3px);
		}
		80% {
			transform: translateX(3px);
		}
	}

	.wobble {
		animation: wobble 0.8s ease-in-out 0.3s 3;
	}

	/* The header token balance. Styled like the Tokens pill but compact — no
	   trailing "tokens" word — since it sits in a dense row of header links. */
	.balance {
		font-size: var(--small-font-size);
		text-decoration: none;
		color: var(--foreground-color);
		background-color: var(--salient-color-faded);
		padding: var(--spacing-half);
		border-radius: var(--roundedness);
		white-space: nowrap;
	}

	.balance .star {
		color: var(--salient-color);
	}

	.balance.changed {
		animation: balance-flash 1.2s ease-out;
	}

	@keyframes balance-flash {
		0% {
			transform: scale(1);
		}
		15% {
			transform: scale(1.18);
			background-color: var(--salient-color);
			color: var(--background-color);
		}
		100% {
			transform: scale(1);
		}
	}

	/* A balance that animates on navigation is exactly the kind of motion a
	   reduced-motion preference is asking us to drop. The number still updates;
	   it just arrives instead of counting. */
	@media (prefers-reduced-motion: reduce) {
		.balance.changed {
			animation: none;
		}
		.wobble {
			animation: none;
		}
	}

	.details {
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
		align-items: baseline;
		font-size: var(--small-font-size);
		padding-left: calc(var(--spacing) / 2);
		padding-right: calc(var(--spacing) / 2);
		padding-bottom: calc(var(--spacing) / 2);
		border-block-end: var(--border-color) solid var(--border-width);
	}
</style>
