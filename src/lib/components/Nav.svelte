<script lang="ts">
	import { goto } from '$app/navigation';
	import Banners from '$lib/components/Banners.svelte';
	import Text from '$lib/locales/Text.svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import { untrack } from 'svelte';
	import { Tween } from 'svelte/motion';
	import { cubicOut } from 'svelte/easing';
	import { getAuth } from '../../routes/Auth.svelte';
	import { getPendingActions } from '../../routes/feedback.svelte';
	import Button from './Button.svelte';
	import Dots from './Dots.svelte';
	import { ScholarLabel, TokenLabel } from './Labels';
	import Link from './Link.svelte';
	import Logo from './Logo.svelte';
	import Overflow from './Overflow.svelte';
	import measure from './measure';

	const locale = getLocaleContext();

	let auth = getAuth();

	let pending = $derived(getPendingActions());

	const { breadcrumbs, tokens = 0 }: { breadcrumbs: [string, string][]; tokens?: number } =
		$props();

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
</script>

<header use:measure={'--nav-height'}>
	<div class="nav">
		<!-- The mark, where the word "Home" used to be. A link to a static landing page is
		     not worth a word of a row that has to fit on a phone, but the mark still has to
		     be somewhere, and the one place every page agrees on is here. -->
		<a class="home" href="/" title={locale().header.home} aria-label={locale().header.home}>
			<Logo size="1.5em" testid="nav-logo" />
		</a>
		{#each breadcrumbs as [url, label]}
			<small>&gt;</small>
			<div class="link crumb">
				<!-- Venue and submission crumbs used to be built here too; the venue bar names
				     the venue on every route inside one, so what is left reaches scholars,
				     currencies and help articles. -->
				<Link size="small" to={url} icon={url.startsWith('/scholar') ? ScholarLabel : null}
					>{label}</Link
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
				<!-- Outside the overflow on purpose. The balance is the one thing in this row
				     that changes on its own, so it is the one thing worth keeping in view at
				     every width. -->
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
			{/if}
			<Overflow strings={(l) => l.header.menu} testid="site-menu">
				<div class="link">
					<Link size="small" to="/venues"><Text path={(l) => l.header.venues} /></Link>
				</div>
				{#if auth().isAuthenticated()}
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
			</Overflow>
		</div>
	</div>
	<Banners />
</header>

<style>
	header {
		/* The upper of two sticky bands. The page's title block in Page.svelte pins
		   directly beneath it, offset by the height measured here into
		   `--nav-height`. This one keeps the higher z-index so it stays on top if
		   that measurement is ever momentarily stale. */
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
		/* Deliberately not `wrap`, which is what this row did until #176. Wrapping is how a
		   crowded header answered a narrow screen by growing a second and third line, until
		   the fixed chrome was half the viewport on a phone. Now the links that do not fit
		   collapse into `Overflow` instead, and the one thing left that can genuinely run
		   long — a breadcrumb label — truncates below. */
		flex-wrap: nowrap;
		gap: calc(var(--spacing) / 2);
		align-items: center;
		background: var(--background-color);
		/* The containing block for the overflow panel, which is absolutely positioned so
		   that opening it cannot change the height measured into `--nav-height`. */
		position: relative;
	}

	.link {
		display: inline-block;
	}

	.home {
		display: inline-flex;
		align-items: center;
		color: var(--salient-color);
		flex: none;
	}

	/* A breadcrumb label is venue- and scholar-authored, so it has no length limit worth
	   relying on. In a row that no longer wraps it is the one item that has to be allowed
	   to lose rather than push everything else off the end. */
	.crumb {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
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
		flex-wrap: nowrap;
		gap: var(--spacing);
		margin-inline-start: auto;
		align-items: center;
		flex: none;
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
	}
</style>
