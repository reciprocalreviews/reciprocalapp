<script lang="ts">
	import { goto } from '$app/navigation';
	import Text from '$lib/locales/Text.svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import type PageHeader from '$routes/PageHeader';
	import { getContext } from 'svelte';
	import { getAuth } from '../../routes/Auth.svelte';
	import { getPendingActions } from '../../routes/feedback.svelte';
	import Button from './Button.svelte';
	import Dots from './Dots.svelte';
	import EditableText from './EditableText.svelte';
	import { ScholarLabel, SubmissionLabel, VenueLabel } from './Labels';
	import Lead from './Lead.svelte';
	import Link from './Link.svelte';
	import Loading from './Loading.svelte';

	const locale = getLocaleContext();

	const routes = [
		{ path: '/', label: locale().header.home },
		{ path: '/venues', label: locale().header.venues }
	];

	let auth = getAuth();

	let pending = $derived(getPendingActions());

	const { breadcrumbs }: { breadcrumbs: [string, string][] } = $props();

	const pageHeader = getContext<PageHeader>('pageHeader');
</script>

<header>
	<div class="nav">
		{#each routes as route}
			<div class="link">
				<Link size="small" to={route.path}>{route.label}</Link>
			</div>
		{/each}
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
			<div class="feedback">
				{#if pending > 0}
					{#if pending > 1}{pending}{/if}
					<Dots></Dots>
				{:else}✔ {locale().header.saved}{/if}
			</div>
			{#if auth().isAuthenticated()}
				<div class="link">
					<Link size="small" to="/scholar/{auth().getUserID()}">{auth().user?.email}</Link>
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
	</div>
	{#if pageHeader?.title}
		<div class="page-header">
			<h1 class:wobble={pageHeader.wobble} data-testid="page-header">
				<span class="emoji">{pageHeader.icon}</span>
				{#if pageHeader.edit}
					<EditableText
						text={pageHeader.title}
						valid={pageHeader.edit.valid}
						edit={pageHeader.edit.update}
						strings={(l) => ({ placeholder: pageHeader.edit!.placeholder(l) })}
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
		padding-top: var(--spacing-half);
		background: var(--background-color);
		margin-bottom: var(--spacing);
		overflow-x: clip;
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
