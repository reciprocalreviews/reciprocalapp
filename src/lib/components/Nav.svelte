<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
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

	/** Whether the reader is already on the page the mark links to. */
	let home = $derived(page.url.pathname === '/');

	/** The row whose width decides what fits. */
	let row = $state<HTMLElement | undefined>(undefined);

	/**
	 * What the account menu offers, as a list rather than as markup: `Overflow` has to be
	 * able to put some of these in the row and the rest behind its control, and a snippet
	 * is not something you can measure or move one child of. Ordered by how readily they
	 * are given up — the row collapses from the end.
	 */
	type Account =
		| { id: 'profile'; to: string; label: string }
		| { id: 'login'; to: string; label: string }
		| { id: 'logout' };

	const account = $derived<Account[]>(
		auth().isAuthenticated()
			? [
					{
						id: 'profile',
						to: `/scholar/${auth().getUserID()}`,
						label: locale().header.link.profile
					},
					{ id: 'logout' }
				]
			: [{ id: 'login', to: '/login', label: locale().header.link.login }]
	);

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

{#snippet accountItem(entry: Account)}
	{#if entry.id === 'logout'}
		<Button
			small
			testid="logout-button"
			strings={(l) => l.component.header.logout}
			action={() => {
				auth().signOut();
				goto('/login');
			}}
		/>
	{:else}
		<Link size="small" to={entry.to}>{entry.label}</Link>
	{/if}
{/snippet}

<header use:measure={'--nav-height'}>
	<div class="nav" bind:this={row}>
		<!-- The mark, where the word "Home" used to be. A link to a static landing page is
		     not worth a word of a row that has to fit on a phone, but the mark still has to
		     be somewhere, and the one place every page agrees on is here.

		     It stops being a link once you are home, by the same rule `Link.svelte` applies
		     to every other link in the chrome: no `href`, and `aria-current` instead. The
		     element stays put either way, so the row does not change width between routes. -->
		<a
			class="home"
			class:inactive={home}
			href={home ? null : '/'}
			aria-current={home ? 'page' : null}
			title={locale().header.home}
			aria-label={locale().header.home}
		>
			<Logo size="1.5em" testid="nav-logo" />
		</a>
		<!-- Venues sits here, with the navigation, rather than off in the account group on
		     the right: it is a route into the platform's content, not something about you.
		     It never collapses — it is one short word, and it is the only way in. -->
		<div class="link">
			<Link size="small" to="/venues"><Text path={(l) => l.header.venues} /></Link>
		</div>
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
		<!-- What used to be `margin-inline-start: auto` on the account group. An auto margin
		     cannot be switched off for the length of a measurement, and a row whose free
		     space is spent on one reports its full width as needed — so the overflow would
		     measure as always fitting and nothing would ever collapse. A spacer is the same
		     layout and can be told to stand aside. -->
		<div class="slack" aria-hidden="true"></div>
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
			<Overflow
				strings={(l) => l.header.menu}
				testid="site-menu"
				items={account}
				key={(entry) => entry.id}
				item={accountItem}
				{row}
			/>
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
		/* Declared, not discovered. What is in this row changes with the width — Logout
		   collapses into the overflow and the ☰ takes its place, and a small Button and the
		   ☰ are not the same height — and this row's height IS `--nav-height`, the sticky
		   offset for every band below it. A row that grew a few pixels when it collapsed
		   would move the whole page vertically on a resize, which is the failure
		   Page.svelte and breadcrumbs.ts both exist to prevent. */
		min-height: var(--chrome-row-height);
		/* The containing block for the overflow panel, which is absolutely positioned so
		   that opening it cannot change the height measured into `--nav-height`. */
		position: relative;
	}

	.link {
		display: inline-block;
		flex: none;
	}

	/* Takes the slack the account group used to claim with `margin-inline-start: auto`. */
	.slack {
		flex: 1 1 0;
		min-width: 0;
	}

	/* The freeze, and the contract Overflow.svelte depends on: for the length of one
	   unpainted measurement, nothing in this row absorbs. Anything added here that can
	   shrink has to be named below too, or the row measures as always fitting, no link ever
	   collapses, and there is no error and no tell at desktop width to say so. */
	/* `:global` on the attribute half is load-bearing, not stylistic: `data-fitting` is
	   written by JavaScript during a measurement, so Svelte's CSS pruner cannot see it and
	   drops the whole rule as unused — silently, and with it the freeze. */
	:global(.nav[data-fitting]) .slack {
		display: none;
	}

	:global(.nav[data-fitting]) .crumb {
		flex-shrink: 0;
	}

	.home {
		display: inline-flex;
		align-items: center;
		color: var(--salient-color);
		flex: none;
	}

	/* On the landing page the mark is where you already are, so it stops offering to take
	   you there — no pointer, and no focus ring on something that does nothing. */
	.home.inactive {
		cursor: default;
	}

	/* A breadcrumb label is venue- and scholar-authored, so it has no length limit worth
	   relying on. In a row that no longer wraps it is the one item that has to be allowed
	   to lose rather than push everything else off the end. */
	.crumb {
		flex: 0 1 auto;
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
		align-items: center;
		flex: none;
		/* The containing block for the overflow's panel and for its idle control, both of
		   which are absolutely positioned so that neither takes part in the row's height. */
		position: relative;
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
